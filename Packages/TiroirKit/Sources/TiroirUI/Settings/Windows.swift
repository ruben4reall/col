import AppKit
import SwiftUI
import TiroirCore

/// Hosts the welcome and Settings in dark windows. Tiroir shows in the Dock and the app switcher only while one of
/// them is open, the way menu bar apps do.
@MainActor
public final class WindowPresenter: NSObject, NSWindowDelegate {
    private var welcome: NSWindow?
    private var settings: NSWindow?
    public var onWelcomeClosed: (() -> Void)?
    /// Shows windows without taking the keyboard or bringing Tiroir to the front (captures).
    public var isQuiet = false

    public override init() {}

    public func showWelcome(model: InterfaceModel, welcomeModel: WelcomeModel, onFinish: @escaping () -> Void) {
        if let welcome {
            present(welcome)
            return
        }
        let view = WelcomeView(model: model, welcome: welcomeModel) { [weak self] in
            onFinish()
            self?.welcome?.close()
        }
        let window = makeWindow(content: view, title: Strings.welcomeWindowTitle, size: CGSize(width: 680, height: 600), resizable: false)
        welcome = window
        present(window)
    }

    public func showSettings(model: InterfaceModel, pane: SettingsPane? = nil) {
        if let pane { model.settingsPane = pane }
        if let settings {
            present(settings)
            return
        }
        let window = makeWindow(content: SettingsView(model: model), title: Strings.settingsWindowTitle, size: CGSize(width: 960, height: 700), resizable: true)
        window.setFrameAutosaveName("TiroirSettings")
        settings = window
        present(window)
    }

    public var isWelcomeOpen: Bool { welcome != nil }
    public var isSettingsOpen: Bool { settings != nil }

    public func closeAll() {
        welcome?.close()
        settings?.close()
    }

    private func makeWindow<Content: View>(content: Content, title: String, size: CGSize, resizable: Bool) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = resizable ? .visible : .hidden
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Theme.night)
        window.contentViewController = NSHostingController(rootView: QuietCapture(isQuiet: isQuiet, content: content))
        window.setContentSize(size)
        window.delegate = self
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        if isQuiet {
            window.orderFrontRegardless()
            return
        }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === welcome {
            welcome = nil
            onWelcomeClosed?()
        }
        if window === settings { settings = nil }
        if welcome == nil, settings == nil, !isQuiet {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

/// A short message under the menu bar for a few seconds: an icon that could not open, a move that failed.
@MainActor
public final class Toast {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    public init() {}

    public func show(_ message: String, near anchor: CGRect?) {
        hideTask?.cancel()
        panel?.orderOut(nil)
        let content = Text(verbatim: message)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            .padding(Theme.panelShadowRoom)
        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize
        let room = Theme.panelShadowRoom
        let center = anchor.map { CGPoint(x: $0.midX, y: $0.midY) } ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let x = anchor.map { min(max($0.midX - size.width / 2, visible.minX + 8 - room), visible.maxX - size.width - 8 + room) } ?? (visible.midX - size.width / 2)
        let panel = NSPanel(contentRect: CGRect(x: x, y: visible.maxY - size.height - 8 + room, width: size.width, height: size.height),
                            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.contentView = hosting
        panel.orderFrontRegardless()
        self.panel = panel
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
            self?.panel = nil
        }
    }
}

/// Windows shown without taking the keyboard (captures while someone works) draw their controls as in the window in
/// front, so pictures show Tiroir as people see it.
private struct QuietCapture<Content: View>: View {
    let isQuiet: Bool
    let content: Content

    var body: some View {
        if isQuiet {
            content.environment(\.controlActiveState, .key)
        } else {
            content
        }
    }
}
