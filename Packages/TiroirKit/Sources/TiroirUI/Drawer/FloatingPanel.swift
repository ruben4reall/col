import AppKit
import SwiftUI
import TiroirCore

/// A borderless panel just under the menu bar that takes the keyboard without bringing Tiroir to the front: the app
/// the person was using stays active (spec 6.2).
final class FloatingPanel: NSPanel {
    var onClose: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], backing: .buffered, defer: true)
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        isFloatingPanel = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        // The shadow comes from SwiftUI, around the rounded glass (Theme.panelShadowRoom).
        hasShadow = false
        isMovable = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }
}

/// Opens and closes one floating panel at a time: a drawer, the All drawer, or search. A click anywhere else, a switch
/// of Space or of app closes it.
@MainActor
public final class PanelController {
    private var panel: FloatingPanel?
    private var outsideMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    public private(set) var openTarget: StatusItemsController.Target?
    public private(set) var isSearchOpen = false
    /// Shows panels without taking the keyboard (captures while someone works).
    public var isQuiet = false

    public init() {}

    public var isOpen: Bool { panel?.isVisible == true }

    /// Shows `content` under `anchor` (AppKit coordinates), centered on it and kept on its screen.
    public func show<Content: View>(_ content: Content, under anchor: CGRect, target: StatusItemsController.Target?) {
        close()
        let panel = FloatingPanel()
        let room = Theme.panelShadowRoom
        let hosting = NSHostingView(rootView: content.padding(room).preferredColorScheme(nil))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        // The glass itself starts `room` inside the window: its top edge sits 6 points under the anchor.
        var origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.minY - 6 + room - size.height)
        origin.x = min(max(origin.x, visible.minX + 8 - room), visible.maxX - size.width - 8 + room)
        origin.y = max(origin.y, visible.minY + 8 - room)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.onClose = { [weak self] in self?.close() }
        self.panel = panel
        openTarget = target
        isSearchOpen = target == nil
        panel.orderFrontRegardless()
        guard !isQuiet else { return }
        panel.makeKey()
        watchForDismissal()
    }

    /// Shows search under the menu bar, centered on the screen that holds the pointer.
    public func showCentered<Content: View>(_ content: Content, width: CGFloat) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let anchor = CGRect(x: visible.midX - 1, y: visible.maxY - 6, width: 2, height: 1)
        show(content.frame(width: width), under: anchor, target: nil)
    }

    public func close() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer); NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        panel?.orderOut(nil)
        panel = nil
        openTarget = nil
        isSearchOpen = false
    }

    /// Resizes the open panel to its content, keeping its top edge (the drawer grows downwards as a filter changes).
    public func fitToContent() {
        guard let panel, let content = panel.contentView else { return }
        let size = content.fittingSize
        var frame = panel.frame
        frame.origin.y = frame.maxY - size.height
        frame.size = size
        panel.setFrame(frame, display: true, animate: false)
    }

    private func watchForDismissal() {
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.close() }
            })
        }
    }
}
