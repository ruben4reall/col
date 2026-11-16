import Foundation
import ColCore
import Observation

/// The widgets of the island's Widgets place: those pushed by programs and devices (`colctl widget set`, the local
/// socket, Col Connect, extensions), and those read from an address. Addresses are read only while the place shows,
/// at the interval the user chose: nothing runs at rest.
@MainActor
@Observable
final class WidgetCenter {
    struct Entry: Identifiable, Equatable {
        var id: String { widget.id }
        var widget: WidgetRequest
        /// When its figures arrived; distantPast for a widget still waiting for its first read.
        var updated: Date
        /// Read from an address, rather than pushed.
        var fromURL = false
        /// Why its last read failed.
        var error: String?

        var isWaiting: Bool { updated == .distantPast }
    }

    enum Call: Equatable {
        case calling, done, failed
    }

    /// Pushed widgets the place holds at most: a device that keeps pushing new ids is refused once it is full.
    static let maximumPushed = 32

    /// Pushed widgets, in the order they first arrived.
    private(set) var pushed: [Entry] = []
    /// The widgets read from an address, as the user set them up.
    private(set) var definitions: [APIWidget]
    /// What each address gave at its last read.
    private(set) var read: [String: Entry] = [:]
    /// A button pressed for the first time: its address waits for the user's yes.
    var confirming: (widget: String, button: WidgetButton)?
    /// What a button's call is doing, by widget id and button index.
    private(set) var calls: [String: Call] = [:]

    @ObservationIgnored var post: ((Activity) -> Void)?
    @ObservationIgnored var remove: ((String) -> Void)?
    @ObservationIgnored private var watchers = 0
    @ObservationIgnored private var polls: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var lastRead: [String: Date] = [:]
    @ObservationIgnored private var saving: Task<Void, Never>?
    /// Where pushed widgets are kept between launches; nil keeps them in memory only, as in tests.
    @ObservationIgnored private let file: URL?
    /// Reads: no cookies, no cache, nothing kept, and a redirect only within the address's own origin, so the headers
    /// the user gave never reach another host.
    @ObservationIgnored let session = WidgetCenter.makeSession(redirects: .sameOrigin)
    /// Button calls: the same, and never redirected.
    @ObservationIgnored let callSession = WidgetCenter.makeSession(redirects: .none)

    static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Col/Widgets.json")
    }

    init(file: URL? = WidgetCenter.defaultFile, definitions: [APIWidget] = Preferences.apiWidgets) {
        self.file = file
        self.definitions = definitions
        if let file, let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([Saved].self, from: data) {
            pushed = saved.prefix(Self.maximumPushed).compactMap { item in
                (try? item.widget.validated()).map { Entry(widget: $0, updated: item.updated) }
            }
        }
    }

    /// Every widget the place shows: the pushed ones, then those read from an address.
    var entries: [Entry] {
        pushed + definitions.map { definition in
            read[definition.id] ?? Entry(widget: WidgetRequest(id: definition.id, title: definition.name), updated: .distantPast, fromURL: true)
        }
    }

    /// How many widgets the place shows, without building them.
    var count: Int { pushed.count + definitions.count }

    var hasContent: Bool { !pushed.isEmpty || !definitions.isEmpty }

    // MARK: Pushed widgets

    /// Shows or updates a widget, already validated. One that asks for it shows in the closed island too. False when
    /// the place is full and the widget is a new one.
    @discardableResult
    func set(_ widget: WidgetRequest, now: Date = Date()) -> Bool {
        let entry = Entry(widget: widget, updated: now)
        if let index = pushed.firstIndex(where: { $0.id == widget.id }) {
            pushed[index] = entry
        } else {
            guard pushed.count < Self.maximumPushed else { return false }
            pushed.append(entry)
        }
        if widget.activity == true {
            post?(widget.activity(updated: now))
        } else {
            remove?(widget.activityID)
        }
        save()
        return true
    }

    /// Takes a pushed widget away; false when there was none of that id.
    @discardableResult
    func remove(_ id: String) -> Bool {
        guard let index = pushed.firstIndex(where: { $0.id == id }) else { return false }
        pushed.remove(at: index)
        remove?("widget." + id)
        save()
        return true
    }

    private struct Saved: Codable {
        var widget: WidgetRequest
        var updated: Date
    }

    /// Writes the pushed widgets a moment after the last change, readable by the user only. A burst of pushes writes
    /// once, after it.
    private func save() {
        guard let file else { return }
        saving?.cancel()
        saving = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled,
                  let data = try? JSONEncoder().encode(self.pushed.map { Saved(widget: $0.widget, updated: $0.updated) })
            else { return }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            try? data.write(to: file, options: [.atomic])
            chmod(file.path, 0o600)
        }
    }

    // MARK: Widgets read from an address

    /// The place shows: addresses are read now if their last read is old, then at their interval, until it hides.
    func watch() {
        watchers += 1
        if watchers == 1 { startReading() }
    }

    func unwatch() {
        watchers = max(0, watchers - 1)
        if watchers == 0 { stopReading() }
    }

    var isWatched: Bool { watchers > 0 }

    func setDefinitions(_ definitions: [APIWidget]) {
        // A widget removed, or a header it no longer sends, takes its value out of the Keychain.
        for old in self.definitions {
            let kept = definitions.first { $0.id == old.id }?.headers ?? []
            for name in old.headers where !kept.contains(name) { Self.setHeaderValue(nil, name, of: old.id) }
        }
        self.definitions = definitions
        read = read.filter { id, _ in definitions.contains { $0.id == id } }
        Preferences.apiWidgets = definitions
        if watchers > 0 {
            stopReading()
            // A changed address or mapping is read again at once.
            lastRead = [:]
            startReading()
        }
    }

    private func startReading() {
        for definition in definitions where polls[definition.id] == nil {
            polls[definition.id] = Task { @MainActor [weak self] in
                while !Task.isCancelled, let center = self {
                    let elapsed = center.lastRead[definition.id].map { Date().timeIntervalSince($0) } ?? .infinity
                    if elapsed >= definition.interval - 1 {
                        await center.refresh(definition)
                        try? await Task.sleep(for: .seconds(definition.interval))
                    } else {
                        // Read a moment ago, before the place hid: the next read keeps the interval.
                        try? await Task.sleep(for: .seconds(definition.interval - elapsed))
                    }
                }
            }
        }
    }

    private func stopReading() {
        polls.values.forEach { $0.cancel() }
        polls.removeAll()
    }

    /// Reads one address now and shows what it gave, or why it gave nothing.
    func refresh(_ definition: APIWidget) async {
        lastRead[definition.id] = Date()
        do {
            var widget = try await Self.read(definition, session: session).widget
            // Read only while the place shows: never in the closed island, where it would go stale unseen.
            widget.activity = nil
            read[definition.id] = Entry(widget: widget, updated: Date(), fromURL: true)
        } catch {
            var entry = read[definition.id] ?? Entry(widget: WidgetRequest(id: definition.id, title: definition.name), updated: .distantPast, fromURL: true)
            entry.error = Self.describe(error)
            read[definition.id] = entry
        }
    }

    enum ReadError: Error, Equatable {
        case badURL
        case status(Int)
        case tooLarge
    }

    /// The most an address may answer: a widget's JSON is small.
    static let maximumAnswer = 1 << 20

    /// Reads an address with the definition's headers (their values from the Keychain, or `values`), and maps the
    /// answer.
    static func read(_ definition: APIWidget, session: URLSession, headers values: [String: String]? = nil)
        async throws -> (data: Data, widget: WidgetRequest, missing: [String]) {
        var headers: [String: String] = [:]
        for name in definition.headers where APIWidget.isValidHeaderName(name) {
            if let value = values?[name] ?? headerValue(name, of: definition.id) { headers[name] = value }
        }
        let data = try await fetch(definition.url, headers: headers, session: session)
        let mapped = try definition.widget(from: data)
        return (data, mapped.widget, mapped.missing)
    }

    /// One read of an address: a 2xx answer of `maximumAnswer` bytes at most, read as it arrives and dropped past
    /// that size.
    static func fetch(_ address: String, headers: [String: String], session: URLSession) async throws -> Data {
        guard WidgetButton.isCallable(address), let url = URL(string: address) else { throw ReadError.badURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in headers where APIWidget.isValidHeaderName(name) { request.setValue(value, forHTTPHeaderField: name) }
        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw ReadError.status(http.statusCode) }
        guard response.expectedContentLength <= Int64(maximumAnswer) else { throw ReadError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > maximumAnswer { throw ReadError.tooLarge }
        }
        return data
    }

    enum Redirects {
        /// Within the address's own scheme, host and port.
        case sameOrigin
        case none
    }

    static func makeSession(redirects: Redirects) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: RedirectPolicy(redirects), delegateQueue: nil)
    }

    static func headerValue(_ name: String, of widget: String) -> String? {
        Keychain.token(for: "\(widget).\(name.lowercased())", service: Keychain.widgets)
    }

    static func setHeaderValue(_ value: String?, _ name: String, of widget: String) {
        Keychain.setToken(value, for: "\(widget).\(name.lowercased())", service: Keychain.widgets)
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case ReadError.badURL: String(localized: "The address is not an http or https one.", bundle: .module)
        case ReadError.status(let code) where (300..<400).contains(code):
            String(localized: "The address sends Col elsewhere (\(code)): give the address it leads to.", bundle: .module)
        case ReadError.status(let code): String(localized: "The address answered \(code).", bundle: .module)
        case ReadError.tooLarge: String(localized: "The answer is too large for a widget.", bundle: .module)
        case APIWidget.Invalid.notJSON: String(localized: "The answer is not JSON.", bundle: .module)
        case APIWidget.Invalid.badWidget(let invalid): invalid.localizedMessage
        default: error.localizedDescription
        }
    }

    // MARK: Buttons

    /// A button was pressed: its address is called, once the user has said yes to this widget's button calling it.
    func press(_ button: WidgetButton, of widget: String) {
        if Preferences.confirmedWidgetCalls.contains(button.confirmationKey(widget: widget)) {
            call(button, of: widget)
        } else {
            confirming = (widget, button)
        }
    }

    func confirm() {
        guard let (widget, button) = confirming else { return }
        confirming = nil
        Preferences.confirmedWidgetCalls.insert(button.confirmationKey(widget: widget))
        call(button, of: widget)
    }

    func cancelConfirmation() {
        confirming = nil
    }

    static func callKey(_ widget: String, _ button: WidgetButton) -> String { button.confirmationKey(widget: widget) }

    private func call(_ button: WidgetButton, of widget: String) {
        guard let valid = button.validated(), let url = URL(string: valid.url) else { return }
        let key = Self.callKey(widget, button)
        calls[key] = .calling
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.httpMethod = valid.resolvedMethod
        if valid.resolvedMethod == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["widget": widget, "button": valid.title], options: [.sortedKeys])
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let succeeded: Bool
            // Not redirected: a 3xx is the answer of the address the user said yes to.
            if let (_, response) = try? await self.callSession.data(for: request), let http = response as? HTTPURLResponse {
                succeeded = (200..<400).contains(http.statusCode)
            } else {
                succeeded = false
            }
            self.calls[key] = succeeded ? .done : .failed
            try? await Task.sleep(for: .seconds(2))
            if self.calls[key] != .calling { self.calls[key] = nil }
        }
    }
}

/// Where a widget's request may be redirected: within its own origin, or nowhere. A redirect refused leaves its 3xx
/// as the answer.
final class RedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    let redirects: WidgetCenter.Redirects

    init(_ redirects: WidgetCenter.Redirects) {
        self.redirects = redirects
    }

    /// Same scheme, host and port, the default ports counted.
    static func sameOrigin(_ a: URL?, _ b: URL?) -> Bool {
        guard let a, let b, let schemeA = a.scheme?.lowercased(), let schemeB = b.scheme?.lowercased(),
              let hostA = a.host?.lowercased(), let hostB = b.host?.lowercased()
        else { return false }
        func port(_ url: URL, _ scheme: String) -> Int? { url.port ?? (scheme == "https" ? 443 : scheme == "http" ? 80 : nil) }
        return schemeA == schemeB && hostA == hostB && port(a, schemeA) == port(b, schemeB)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        switch redirects {
        case .none: completionHandler(nil)
        case .sameOrigin: completionHandler(Self.sameOrigin(task.originalRequest?.url, request.url) ? request : nil)
        }
    }
}

extension WidgetRequest.Invalid {
    /// The message in the user's language, for the island and the settings. The API answers in English.
    var localizedMessage: String {
        switch self {
        case .missingID: String(localized: "A widget needs an id.", bundle: .module)
        case .badID: String(localized: "A widget’s id is 1 to 64 letters, digits, dots, dashes or underscores.", bundle: .module)
        case .badButton(let index): String(localized: "Button \(index + 1) needs a title and an http or https address.", bundle: .module)
        case .tooManyButtons: String(localized: "A widget has three buttons at most.", bundle: .module)
        }
    }
}
