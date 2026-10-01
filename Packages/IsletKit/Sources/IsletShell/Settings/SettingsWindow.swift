import AppKit
import IsletCore
import Observation
import SwiftUI

/// The settings window. It opens below the open island, never under it, centred on the notch, and gives Islet a Dock
/// icon while it is open so it can be found with ⌘Tab like any other window. Settings are rarely open: the window is
/// released when it closes, and remembers only its size.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    private let model = SettingsModel()
    var extensions: ExtensionRunner?

    static let preferredSize = NSSize(width: 960, height: 680)
    static let minimumSize = NSSize(width: 820, height: 560)
    /// Air between the bottom of the open island and the top of the window.
    static let gapBelowIsland: CGFloat = 24

    func show(_ pane: SettingsPane? = nil) {
        if let pane { model.pane = pane }
        let window = self.window ?? makeWindow()
        WindowPresence.shared.add(window)
        // The app becomes a regular one a moment after it asks to: show the window once it has.
        DispatchQueue.main.async {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            // Shown even when macOS keeps another app in front, as after a launch from Terminal.
            window.orderFrontRegardless()
            // Nothing selected at first: typing does not land in the search field by surprise.
            window.makeFirstResponder(nil)
            // `-IsletSettingsScroll 300` scrolls the pane, for screenshots of its header over scrolled content.
            let scroll = UserDefaults.standard.double(forKey: "IsletSettingsScroll")
            if scroll > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { Self.scrollPane(in: window, by: scroll) }
            }
        }
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(model: model, extensions: extensions))
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Islet Settings", bundle: .module)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Opened from the island, which is on every Space: the window comes to the Space in use.
        window.collectionBehavior.formUnion([.fullScreenNone, .moveToActiveSpace])
        window.isReleasedWhenClosed = false
        window.minSize = Self.minimumSize
        window.delegate = self
        place(window)
        self.window = window
        return window
    }

    /// Below the open island with some air, centred on the notch, on the island's screen. The size is the last one
    /// the user gave the window, shortened if the screen has no room for it.
    private func place(_ window: NSWindow) {
        guard let anchor = IslandController.shared?.windowAnchor ?? WindowAnchor.main else {
            window.center()
            return
        }
        let visible = anchor.screen.visibleFrame
        var size = UserDefaults.standard.string(forKey: "settingsWindowSize").map(NSSizeFromString) ?? Self.preferredSize
        if size.width < Self.minimumSize.width || size.height < Self.minimumSize.height { size = Self.preferredSize }
        // `-IsletSettingsHeight 900` opens it taller, for screenshots that show a whole pane.
        let forced = UserDefaults.standard.double(forKey: "IsletSettingsHeight")
        if forced > 0 { size.height = forced }
        let top = min(visible.maxY, anchor.islandBottom - Self.gapBelowIsland)
        size.height = max(min(size.height, top - visible.minY - 16), min(Self.minimumSize.height, visible.height - 16))
        size.width = min(size.width, visible.width - 32)
        let x = min(max(anchor.centerX - size.width / 2, visible.minX + 16), visible.maxX - size.width - 16)
        let y = max(top - size.height, visible.minY + 8)
        window.setFrame(NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height), display: false)
    }

    private static func scrollPane(in window: NSWindow, by distance: CGFloat) {
        func scrollViews(in view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
        }
        // The widest scroll view is the pane's form; the sidebar's list is narrower.
        guard let form = window.contentView.flatMap(scrollViews)?.max(by: { $0.frame.width < $1.frame.width }) else { return }
        form.contentView.scroll(to: NSPoint(x: 0, y: form.contentView.bounds.minY + distance))
        form.reflectScrolledClipView(form.contentView)
    }

    func windowWillClose(_ notification: Notification) {
        if let window {
            UserDefaults.standard.set(NSStringFromSize(window.frame.size), forKey: "settingsWindowSize")
            WindowPresence.shared.remove(window)
        }
        window = nil
    }
}

/// Where windows that open from the island go: the island's screen, the bottom of the open island and the middle of
/// the notch, in screen coordinates.
struct WindowAnchor {
    let screen: NSScreen
    let islandBottom: CGFloat
    let centerX: CGFloat

    /// Without a running island: the main screen, as if an island of standard size hung from its top.
    @MainActor static var main: WindowAnchor? {
        guard let screen = NSScreen.main else { return nil }
        let open = IslandSize.standard.open
        return WindowAnchor(screen: screen, islandBottom: screen.frame.maxY - 32 - open.content, centerX: screen.frame.midX)
    }
}

@MainActor
@Observable
final class SettingsModel {
    var pane: SettingsPane = .general
    var query = ""
}

/// The panes, in the order of the sidebar.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, pages, activities
    case aiApps
    case permissions, shortcuts, developers, about
    var id: String { rawValue }

    enum Group: CaseIterable {
        case island, modules, app

        var title: LocalizedStringResource {
            switch self {
            case .island: LocalizedStringResource("The island", bundle: .settings)
            case .modules: LocalizedStringResource("Modules", bundle: .settings)
            case .app: LocalizedStringResource("Islet", bundle: .settings)
            }
        }

        var panes: [SettingsPane] { SettingsPane.allCases.filter { $0.group == self } }
    }

    var group: Group {
        switch self {
        case .general, .appearance, .pages, .activities: .island
        case .aiApps: .modules
        case .permissions, .shortcuts, .developers, .about: .app
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .general: LocalizedStringResource("General", bundle: .settings)
        case .appearance: LocalizedStringResource("Appearance", bundle: .settings)
        case .pages: LocalizedStringResource("Pages", bundle: .settings)
        case .activities: LocalizedStringResource("Live activities", bundle: .settings)
        case .aiApps: LocalizedStringResource("AI apps", bundle: .settings)
        case .permissions: LocalizedStringResource("Permissions", bundle: .settings)
        case .shortcuts: LocalizedStringResource("Shortcuts and gestures", bundle: .settings)
        case .developers: LocalizedStringResource("Developers", bundle: .settings)
        case .about: LocalizedStringResource("About Islet", bundle: .settings)
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .general: LocalizedStringResource("Startup, screen, privacy and updates.", bundle: .settings)
        case .appearance: LocalizedStringResource("Size, glass and motion, shown on your own screen.", bundle: .settings)
        case .pages: LocalizedStringResource("What the open island shows, page by page.", bundle: .settings)
        case .activities: LocalizedStringResource("What the closed island shows beside the camera.", bundle: .settings)
        case .aiApps: LocalizedStringResource("Your AI apps in the notch: their sessions, their requests, their state.", bundle: .settings)
        case .permissions: LocalizedStringResource("What Islet may use, and for what.", bundle: .settings)
        case .shortcuts: LocalizedStringResource("Every way to open and drive the island.", bundle: .settings)
        case .developers: LocalizedStringResource("The islet command, the local API and extensions.", bundle: .settings)
        case .about: LocalizedStringResource("Version, privacy and credits.", bundle: .settings)
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintbrush.pointed.fill"
        case .pages: "rectangle.split.3x1.fill"
        case .activities: "dot.radiowaves.left.and.right"
        case .aiApps: "sparkles"
        case .permissions: "hand.raised.fill"
        case .shortcuts: "command"
        case .developers: "chevron.left.forwardslash.chevron.right"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .appearance: Theme.coral.color
        case .pages: .orange
        case .activities: .purple
        case .aiApps: Color(red: 0.36, green: 0.42, blue: 1)
        case .permissions: .blue
        case .shortcuts: Color(red: 0.42, green: 0.45, blue: 0.5)
        case .developers: .indigo
        case .about: .gray
        }
    }

    /// Words a search should find this pane by: the names of its settings, in the user's language and in English.
    private var terms: [LocalizedStringResource] {
        let terms: [String.LocalizationValue] = switch self {
        case .general: ["Open Islet at login", "Show the island on", "Step aside in full screen", "Keep recent copies",
                        "Hide the island from screenshots and recordings", "Updates", "Show the Welcome Again…"]
        case .appearance: ["Size when open", "Compact", "Standard", "Large", "Liquid Glass", "Liquid", "Transparent", "Tinted",
                           "Black", "Animation speed", "Open when the pointer rests on the notch", "Delay before opening"]
        case .pages: ["Home", "Shelf", "Clipboard", "Tools", "System", "Live"]
        case .activities: ["Music beside the camera", "Announce new tracks", "Replace the volume and brightness displays",
                           "Headphones and speakers", "Battery card for headphones", "Charging and low battery",
                           "Microphone and camera in use", "Downloads in progress", "Show on the Lock Screen"]
        case .aiApps: ["Claude Code", "Codex", "Gemini CLI", "Cursor", "GitHub Copilot (VS Code)", "Connect", "Allow", "Deny"]
        case .permissions: ["Accessibility", "Calendars", "Bluetooth", "Camera", "Downloads"]
        case .shortcuts: ["Keyboard", "Gestures", "Swipe", "Click", "Trackpad", "Right-click"]
        case .developers: ["The islet command", "API reference", "Extensions", "Writing an extension"]
        case .about: ["Version", "Website", "Source code on GitHub", "Report a problem", "Quit Islet", "Network"]
        }
        return terms.map { LocalizedStringResource($0, bundle: .settings) }
    }

    /// True when the pane, or one of its settings, matches what was typed; accents and case do not count.
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        let resources = [title, summary] + terms
        let words = resources.map { String(localized: $0) } + resources.map { String(describing: $0.key) }
        return words.contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

extension LocalizedStringResource.BundleDescription {
    /// The settings' strings live in this package's catalog.
    static var settings: Self { .atURL(Bundle.module.bundleURL) }
}

struct SettingsView: View {
    @Bindable var model: SettingsModel
    let extensions: ExtensionRunner?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                SettingsSearchField(text: $model.query)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                sidebar
            }
            // A search field placed by `.searchable` would reset this width: the field is drawn here instead.
            .navigationSplitViewColumnWidth(min: 230, ideal: 240, max: 300)
            .onChange(of: model.query) {
                // The first match comes forward as the user types, as in System Settings.
                if !model.pane.matches(model.query), let first = SettingsPane.allCases.first(where: { $0.matches(model.query) }) {
                    model.pane = first
                }
            }
        } detail: {
            detail
                .id(model.pane)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: SettingsWindow.minimumSize.width, minHeight: SettingsWindow.minimumSize.height)
    }

    private var sidebar: some View {
        List(selection: $model.pane) {
            ForEach(SettingsPane.Group.allCases, id: \.self) { group in
                let panes = group.panes.filter { $0.matches(model.query) }
                if !panes.isEmpty {
                    Section {
                        ForEach(panes) { pane in
                            Label {
                                Text(pane.title)
                            } icon: {
                                IconTile(symbol: pane.symbol, tint: pane.tint, size: 22)
                            }
                            .tag(pane)
                        }
                    } header: {
                        Text(group.title)
                    }
                }
            }
        }
        .overlay {
            if SettingsPane.allCases.allSatisfy({ !$0.matches(model.query) }) {
                Text("No Results", bundle: .module)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.pane {
        case .general: GeneralPane()
        case .appearance: AppearancePane()
        case .pages: PagesPane()
        case .activities: LiveActivitiesPane()
        case .aiApps: AIAppsPane()
        case .permissions: PermissionsPane()
        case .shortcuts: ShortcutsPane()
        case .developers: DevelopersPane(extensions: extensions)
        case .about: AboutPane()
        }
    }
}

/// The search field at the top of the sidebar. ⌘F puts the cursor in it; Escape clears it.
private struct SettingsSearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(text: $text) { Text("Search", bundle: .module) }
                .textFieldStyle(.plain)
                .focused($focused)
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(Text("Clear", bundle: .module))
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(focused ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1.5))
        .background {
            Button("") { focused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }
}
