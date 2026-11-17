import AppKit
import ApplicationServices
import os

/// An app that may own menu bar icons.
public struct RunningApp: Sendable, Equatable {
    public var pid: pid_t
    public var bundleID: String
    public var name: String
    public var bundleURL: URL?

    public init(pid: pid_t, bundleID: String, name: String, bundleURL: URL? = nil) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.bundleURL = bundleURL
    }
}

/// One menu bar icon as its app describes it over Accessibility (`AXExtrasMenuBar`).
public struct ExtraItem: Sendable {
    public var app: RunningApp
    public var frame: CGRect
    public var identifier: String?
    /// The icon's own words: its description, title or help, whichever it gives.
    public var label: String?
    public var element: AXElement
}

/// Reads the icons of every running app, concurrently, with a short timeout per app.
public final class ExtrasReader: @unchecked Sendable {
    /// An app that did not answer is left alone this long.
    public static let backoff: TimeInterval = 30

    private let lock = OSAllocatedUnfairLock(initialState: [pid_t: Date]())
    private let timeout: Float

    public init(timeout: Float = 0.2) {
        self.timeout = timeout
    }

    /// Apps that can own icons: every app with a user interface, never background-only processes, never Tiroir.
    @MainActor
    public static func candidates(excludingPID ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> [RunningApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy != .prohibited, app.processIdentifier != ownPID, !app.isTerminated,
                  let bundleID = app.bundleIdentifier else { return nil }
            return RunningApp(pid: app.processIdentifier, bundleID: bundleID, name: app.localizedName ?? bundleID, bundleURL: app.bundleURL)
        }
    }

    /// The icons of `apps`, in no particular order.
    public func read(_ apps: [RunningApp]) async -> [ExtraItem] {
        let now = Date()
        let skipped = lock.withLock { state in
            state = state.filter { now.timeIntervalSince($0.value) < Self.backoff }
            return Set(state.keys)
        }
        let targets = apps.filter { !skipped.contains($0.pid) }
        return await withTaskGroup(of: [ExtraItem].self) { group in
            for app in targets {
                group.addTask { [timeout, lock] in
                    let (items, answered) = Self.items(of: app, timeout: timeout)
                    if !answered {
                        lock.withLock { $0[app.pid] = Date() }
                        Log.accessibility.debug("\(app.bundleID, privacy: .public) did not answer in time")
                    }
                    return items
                }
            }
            var all: [ExtraItem] = []
            for await items in group { all.append(contentsOf: items) }
            return all
        }
    }

    /// Reads one app. `answered` is false when the app did not reply in time.
    static func items(of app: RunningApp, timeout: Float) -> (items: [ExtraItem], answered: Bool) {
        let application = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(application, timeout)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(application, "AXExtrasMenuBar" as CFString, &value)
        guard error == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return ([], error != .cannotComplete)
        }
        let bar = AXElement(value as! AXUIElement) // checked by the type identifier above
        let items = bar.children.compactMap { child -> ExtraItem? in
            guard let frame = child.frame, frame.width > 0, frame.height > 0 else { return nil }
            let label = [child.descriptionText, child.title, child.help]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            return ExtraItem(app: app, frame: frame, identifier: child.identifier, label: label, element: child)
        }
        return (items, true)
    }
}
