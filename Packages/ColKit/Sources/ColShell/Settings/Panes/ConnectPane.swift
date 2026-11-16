import AppKit
import ColCore
import ColPrompter
import SwiftUI

/// Col Connect and the widgets: the server for the devices of the local network, the devices paired with it, and the
/// widgets pushed or read from an address.
struct ConnectPane: View {
    let widgets: WidgetCenter?
    @State var connect = ConnectCenter.shared
    @AppStorage("connectEnabled") private var enabled = false
    @AppStorage("connectAllowsOutside") private var allowsOutside = false
    /// The device whose code and token show, just paired or asked for again.
    @State private var shown: (device: String, token: String)?
    @State private var newName = ""
    @State private var naming = false
    @State private var editing: APIWidget?

    var body: some View {
        PaneScaffold(pane: .connect) {
            Section {
                Toggle(isOn: Binding(get: { enabled }, set: { on in
                    enabled = on
                    Preferences.connectEnabled = on
                    if !on { shown = nil }
                })) {
                    Text("Col Connect", bundle: .module)
                    Text("Lets your phone, a home server, Home Assistant or a build machine on this network push activities and widgets into the island.", bundle: .module)
                }
                if enabled { status }
            } footer: {
                Text("Off until you turn it on. Only the devices you pair can reach Col, each with a token of its own, and only from this network. Allow and Deny for your agents never leave this Mac.", bundle: .module)
            }
            if enabled { devices }
            widgetsSection
            Section {
                Toggle(isOn: Binding(get: { allowsOutside }, set: { allowsOutside = $0; Preferences.connectAllowsOutside = $0 })) {
                    Text("Accept connections from outside this network", bundle: .module)
                    Text("For a Mac you reach through a VPN or a forwarded port. Requests still need a paired device’s token, and travel unencrypted.", bundle: .module)
                }
                .disabled(!enabled)
            } header: {
                Text("Security", bundle: .module)
            }
            Section {
                Link(destination: URL(string: "https://github.com/ruben4reall/col/blob/main/docs/connect.md")!) { Text("Col Connect: Shortcuts, curl and Home Assistant", bundle: .module) }
                Link(destination: URL(string: "https://github.com/ruben4reall/col/blob/main/docs/widgets.md")!) { Text("The widget format", bundle: .module) }
            } header: {
                Text("Documentation", bundle: .module)
            }
        }
        .sheet(item: $editing) { definition in
            APIWidgetEditor(definition: definition, isNew: !(widgets?.definitions.contains { $0.id == definition.id } ?? false)) { saved in
                guard let widgets else { return }
                var all = widgets.definitions
                if let index = all.firstIndex(where: { $0.id == saved.id }) { all[index] = saved } else { all.append(saved) }
                widgets.setDefinitions(all)
            }
        }
    }

    // MARK: Status

    @ViewBuilder private var status: some View {
        switch connect.state {
        case .listening:
            LabeledContent {
                VStack(alignment: .trailing, spacing: 2) {
                    if let address = connect.address {
                        Text(verbatim: address).textSelection(.enabled)
                    }
                    if let bonjour = connect.bonjourAddress {
                        Text(verbatim: bonjour).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                .font(.system(size: 12, design: .monospaced))
            } label: {
                Label { Text("Listening", bundle: .module) } icon: {
                    Image(systemName: "circle.fill").foregroundStyle(.green).font(.system(size: 8))
                }
            }
        case .starting, .stopped:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Starting…", bundle: .module).foregroundStyle(.secondary)
            }
        case .waiting(let reason), .failed(let reason):
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text("Col cannot listen on the network: \(reason)", bundle: .module)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                }
                Text("If macOS kept Col off the local network, turn Col on in Privacy & Security, Local Network.", bundle: .module)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button { PermissionCenter.shared.openLocalNetworkSettings() } label: { Text("Open Local Network Settings…", bundle: .module) }
            }
        }
    }

    // MARK: Devices

    private var devices: some View {
        Section {
            if connect.devices.isEmpty, !naming {
                Text("No device yet. Pair your phone, a home server or a build machine: each one gets a token of its own, which you can take back.", bundle: .module)
                    .foregroundStyle(.secondary)
            }
            ForEach(connect.devices) { device in
                DeviceRow(device: device, showing: shown?.device == device.id) {
                    if shown?.device == device.id {
                        shown = nil
                    } else if let token = connect.token(of: device.id) {
                        shown = (device.id, token)
                    }
                } remove: {
                    if shown?.device == device.id { shown = nil }
                    connect.unpair(device.id)
                }
                if let shown, shown.device == device.id {
                    PairingCard(connect: connect, token: shown.token) {
                        if let token = connect.renewToken(of: device.id) { self.shown = (device.id, token) }
                    }
                }
            }
            if naming {
                HStack {
                    TextField(text: $newName, prompt: Text("iPhone, Home Assistant, build server…", bundle: .module)) {
                        Text("Name", bundle: .module)
                    }
                    .onSubmit(pair)
                    Button(action: pair) { Text("Pair", bundle: .module) }
                        .keyboardShortcut(.defaultAction)
                    Button { naming = false } label: { Text("Cancel", bundle: .module) }
                }
            } else {
                Button {
                    newName = ""
                    naming = true
                } label: {
                    Label { Text("Pair a Device…", bundle: .module) } icon: { Image(systemName: "plus.circle.fill") }
                }
                .buttonStyle(.borderless)
            }
        } header: {
            Text("Devices", bundle: .module)
        } footer: {
            Text("A device sends its token with every request, in an Authorization: Bearer header. Removing a device takes its token back at once.", bundle: .module)
        }
    }

    private func pair() {
        let (device, token) = connect.pair(named: newName)
        naming = false
        shown = (device.id, token)
    }

    // MARK: Widgets

    @ViewBuilder private var widgetsSection: some View {
        if let widgets {
            Section {
                if widgets.entries.isEmpty {
                    Text("Widgets pushed with colctl widget set, the local API, Col Connect or an extension show here, and in the Widgets place you add to a page.", bundle: .module)
                        .foregroundStyle(.secondary)
                }
                ForEach(widgets.entries) { entry in
                    WidgetRow(entry: entry) {
                        if let definition = widgets.definitions.first(where: { $0.id == entry.id }) { editing = definition }
                    } remove: {
                        if entry.fromURL {
                            widgets.setDefinitions(widgets.definitions.filter { $0.id != entry.id })
                        } else {
                            widgets.remove(entry.id)
                        }
                    }
                }
                HStack {
                    Button {
                        editing = APIWidget(name: String(localized: "Widget", bundle: .module), url: "https://")
                    } label: {
                        Label { Text("Add a Widget from a URL…", bundle: .module) } icon: { Image(systemName: "plus.circle.fill") }
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    WidgetsPlaceButton()
                }
            } header: {
                Text("Widgets", bundle: .module)
            } footer: {
                Text("A widget read from an address is read only while it shows in the island, at the interval you choose.", bundle: .module)
            }
        }
    }
}

/// A paired device: its name, when it was last seen and from where.
struct DeviceRow: View {
    let device: ConnectDevice
    let showing: Bool
    let show: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, tint: .blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: device.name)
                Group {
                    if let seen = device.lastSeen {
                        Text("Last seen \(seen.formatted(.relative(presentation: .named))) from \(device.lastAddress ?? "?")", bundle: .module)
                    } else {
                        Text("Not seen yet", bundle: .module)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: show) { Text(showing ? "Hide" : "Show Code", bundle: .module) }
            Button(role: .destructive, action: remove) {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help(Text("Remove this device and take its token back", bundle: .module))
        }
    }

    private var symbol: String {
        let name = device.name.lowercased()
        if name.contains("iphone") || name.contains("phone") { return "iphone" }
        if name.contains("ipad") { return "ipad" }
        if name.contains("home") { return "house.fill" }
        if name.contains("watch") { return "applewatch" }
        return "server.rack"
    }
}

/// The code to scan with the phone, the address and the token to type elsewhere.
struct PairingCard: View {
    let connect: ConnectCenter
    let token: String
    let renew: () -> Void
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            if let link = connect.pairingLink(token: token), let image = QRCode.image(for: link, size: 150) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 128, height: 128)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Scan with your phone’s camera", bundle: .module).font(.system(size: 13, weight: .semibold))
                Text("The page that opens gives the address and the token to copy into a Shortcut. Elsewhere, type them:", bundle: .module)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                    GridRow {
                        Text("Address", bundle: .module).foregroundStyle(.secondary)
                        Text(verbatim: connect.address ?? "…").textSelection(.enabled)
                    }
                    GridRow {
                        Text("Token", bundle: .module).foregroundStyle(.secondary)
                        Text(verbatim: token).textSelection(.enabled)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                HStack {
                    Button {
                        NSPasteboard.general.clearContents()
                        // Concealed: clipboard managers that honour it, Col's own history among them, skip it.
                        NSPasteboard.general.setString(token, forType: .string)
                        NSPasteboard.general.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
                        copied = true
                    } label: { Text(copied ? "Copied" : "Copy Token", bundle: .module) }
                    Button(action: renew) { Text("New Token", bundle: .module) }
                        .help(Text("The device’s current token stops working at once", bundle: .module))
                }
            }
        }
        .padding(.vertical, 6)
    }
}

/// A widget in the list: where it comes from, what it shows, and when.
struct WidgetRow: View {
    let entry: WidgetCenter.Entry
    let edit: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: entry.widget.symbol ?? "square.grid.2x2.fill", tint: entry.widget.resolvedTint == .white ? .indigo : entry.widget.resolvedTint.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: entry.widget.title ?? entry.id)
                Group {
                    if let error = entry.error {
                        Text(verbatim: error).foregroundStyle(.orange)
                    } else if entry.isWaiting {
                        Text("Read when it shows in the island", bundle: .module)
                    } else {
                        Text(verbatim: [entry.widget.shownValue, entry.updated.formatted(.relative(presentation: .named))]
                            .compactMap { $0 }.joined(separator: " · "))
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            Text(verbatim: entry.fromURL ? "URL" : entry.id)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
            if entry.fromURL {
                Button(action: edit) { Text("Edit…", bundle: .module) }
            }
            Button(role: .destructive, action: remove) {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help(Text("Remove", bundle: .module))
        }
    }
}

/// Adds a page with the Widgets place, or says which page has it.
private struct WidgetsPlaceButton: View {
    @State private var deck = Preferences.pageDeck

    var body: some View {
        if let page = deck.firstPage(holding: .widgets) {
            Text("In the island on \(page.title)", bundle: .module)
                .foregroundStyle(.secondary)
                .font(.callout)
        } else {
            Button {
                var edited = Preferences.pageDeck
                var page = edited.add([WidgetStack([.widgets])])
                page.symbol = "square.grid.2x2.fill"
                edited.update(page)
                Preferences.pageDeck = edited
                deck = Preferences.pageDeck
            } label: { Text("Add a Widgets Page", bundle: .module) }
        }
    }
}

/// A widget read from an address: the address, how often, the headers it needs, and how its answer fills the widget,
/// with the answer and the widget it gives side by side.
struct APIWidgetEditor: View {
    @State var definition: APIWidget
    let isNew: Bool
    let save: (APIWidget) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var headers: [Header] = []
    @State private var answer: JSONValue?
    @State private var answerText = ""
    @State private var readError: String?
    @State private var reading = false

    struct Header: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var value: String
    }

    /// `answer` starts the preview from an answer already read.
    init(definition: APIWidget, isNew: Bool, answer: Data? = nil, save: @escaping (APIWidget) -> Void) {
        _definition = State(initialValue: definition)
        self.isNew = isNew
        self.save = save
        if let answer, let document = try? JSONDecoder().decode(JSONValue.self, from: answer) {
            _answer = State(initialValue: document)
            _answerText = State(initialValue: Self.pretty(answer))
        }
        _headers = State(initialValue: definition.headers.map {
            Header(name: $0, value: WidgetCenter.headerValue($0, of: definition.id) ?? "")
        })
    }

    private static let intervals = [1, 5, 15, 30, 60]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Form {
                    Section {
                        TextField(text: $definition.name) { Text("Name", bundle: .module) }
                        TextField(text: $definition.url, prompt: Text(verbatim: "https://api.example.com/now.json")) { Text("Address", bundle: .module) }
                        Picker(selection: $definition.minutes) {
                            ForEach(Self.intervals, id: \.self) { minutes in
                                Text("Every \(minutes) min", bundle: .module).tag(minutes)
                            }
                        } label: { Text("Read", bundle: .module) }
                    } footer: {
                        Text("Read only while the widget shows in the island.", bundle: .module)
                    }
                    Section {
                        ForEach($headers) { $header in
                            HStack {
                                TextField(text: $header.name, prompt: Text(verbatim: "Authorization")) { EmptyView() }
                                    .labelsHidden()
                                    .frame(width: 130)
                                SecureField(text: $header.value, prompt: Text("Value, kept in your Keychain", bundle: .module)) { EmptyView() }
                                    .labelsHidden()
                                Button { headers.removeAll { $0.id == header.id } } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Button { headers.append(Header(name: "", value: "")) } label: {
                            Label { Text("Add a Header", bundle: .module) } icon: { Image(systemName: "plus.circle.fill") }
                        }
                        .buttonStyle(.borderless)
                    } header: {
                        Text("Headers", bundle: .module)
                    }
                    Section {
                        field("Title", $definition.mapping.title, "{name}")
                        field("Value", $definition.mapping.value, "{data.temp}")
                        field("Unit", $definition.mapping.unit, "°C")
                        field("Progress", $definition.mapping.progress, "{battery}")
                        LabeledContent {
                            TextField(value: $definition.mapping.progressMaximum, format: .number, prompt: Text(verbatim: "100")) { EmptyView() }
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                        } label: { Text("Progress out of", bundle: .module) }
                        field("Symbol", $definition.mapping.symbol, "thermometer.medium")
                        field("Colour", $definition.mapping.tint, "orange")
                        ForEach(0..<3, id: \.self) { index in
                            field("Line \(index + 1)", line(index), "Humidity {data.humidity}%")
                        }
                    } header: {
                        Text("What the widget shows", bundle: .module)
                    } footer: {
                        Text("Put a key path of the answer in braces: {data.temp}, {items.0.name}. Leave every field empty when the address answers in Col’s widget format.", bundle: .module)
                    }
                }
                .formStyle(.grouped)
                .frame(minWidth: 400)
                preview
                    .frame(width: 290)
            }
            Divider()
            HStack {
                if let problem {
                    Text(verbatim: problem).foregroundStyle(.orange).font(.callout)
                }
                Spacer()
                Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                    .keyboardShortcut(.cancelAction)
                Button {
                    var saved = definition
                    let kept = headers.filter { !$0.name.isEmpty }
                    saved.headers = kept.map(\.name)
                    // Values of headers no longer listed go too.
                    for name in definition.headers where !saved.headers.contains(name) { WidgetCenter.setHeaderValue(nil, name, of: saved.id) }
                    for header in kept { WidgetCenter.setHeaderValue(header.value, header.name, of: saved.id) }
                    save(saved)
                    dismiss()
                } label: { Text(isNew ? "Add" : "Save", bundle: .module) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
            .padding(14)
        }
        .frame(width: 760, height: 620)
    }

    /// What keeps the widget from being saved.
    private var problem: String? {
        if !definition.isValidURL { return String(localized: "The address must start with http:// or https://.", bundle: .module) }
        if let bad = headers.first(where: { !$0.name.isEmpty && !APIWidget.isValidHeaderName($0.name) }) {
            return String(localized: "“\(bad.name)” is not a header name: letters, digits and dashes only.", bundle: .module)
        }
        return nil
    }

    private func line(_ index: Int) -> Binding<String> {
        Binding {
            index < definition.mapping.lines.count ? definition.mapping.lines[index] : ""
        } set: { value in
            while definition.mapping.lines.count <= index { definition.mapping.lines.append("") }
            definition.mapping.lines[index] = value
            while definition.mapping.lines.last?.isEmpty == true { definition.mapping.lines.removeLast() }
        }
    }

    private func field(_ title: String.LocalizationValue, _ value: Binding<String>, _ example: String) -> some View {
        LabeledContent {
            TextField(text: value, prompt: Text(verbatim: example)) { EmptyView() }
                .labelsHidden()
                .font(.system(size: 12, design: .monospaced))
        } label: {
            Text(String(localized: title, bundle: .module))
        }
    }

    // MARK: Preview

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Preview", bundle: .module).font(.headline)
                Spacer()
                Button(action: read) {
                    if reading { ProgressView().controlSize(.small) } else { Text("Read Now", bundle: .module) }
                }
                .disabled(!definition.isValidURL || reading)
            }
            let mapped = answer.map { document in Result { try definition.widget(from: document) } }
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.black)
                switch mapped {
                case .success(let result)?:
                    WidgetTile(entry: WidgetCenter.Entry(widget: result.widget, updated: Date(), fromURL: true), center: nil)
                        .padding(10)
                        .environment(\.colorScheme, .dark)
                case .failure(let error)?:
                    Text(verbatim: WidgetCenter.describe(error)).foregroundStyle(.orange).font(.callout).padding()
                case nil:
                    Text(readError ?? String(localized: "Read the address to see the widget it gives.", bundle: .module))
                        .foregroundStyle(readError == nil ? Color.secondary : Color.orange)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .frame(height: 144)
            .environment(\.colorScheme, .dark)
            if case .success(let result)? = mapped, !result.missing.isEmpty {
                Text("Nothing at \(result.missing.joined(separator: ", ")) in the answer.", bundle: .module)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            Text("Answer", bundle: .module).font(.headline)
            ScrollView {
                Text(verbatim: answerText.isEmpty ? "–" : answerText)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
        .padding(16)
    }

    private func read() {
        reading = true
        readError = nil
        let values = Dictionary(headers.filter { !$0.name.isEmpty }.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
        let address = definition.url
        Task { @MainActor in
            defer { reading = false }
            do {
                // As the island reads it: within limits, and its headers never sent to another host.
                let data = try await WidgetCenter.fetch(address, headers: values, session: WidgetCenter.makeSession(redirects: .sameOrigin))
                guard let document = try? JSONDecoder().decode(JSONValue.self, from: data) else { throw APIWidget.Invalid.notJSON }
                answer = document
                answerText = Self.pretty(data)
            } catch {
                answer = nil
                answerText = ""
                readError = WidgetCenter.describe(error)
            }
        }
    }

    /// The answer laid out to read, its first few thousand characters, numbers as they were written.
    static func pretty(_ data: Data) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let document = try? JSONDecoder().decode(JSONValue.self, from: data), let pretty = try? encoder.encode(document)
        else { return String(decoding: data.prefix(4000), as: UTF8.self) }
        return String(String(decoding: pretty, as: UTF8.self).prefix(6000))
    }
}
