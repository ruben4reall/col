import AppKit
import SwiftUI
import TiroirCore

/// A borderless panel just under the menu bar that takes the keyboard without bringing Tiroir to the front: the app
/// the person was using stays active (spec 6.2).
@available(macOS 26, *)
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
@available(macOS 26, *)
@MainActor
public final class PanelController {
    private var panel: FloatingPanel?
    private var state: DropState?
    private var outsideMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    public private(set) var openTarget: StatusItemsController.Target?
    public private(set) var isSearchOpen = false
    /// Shows panels without taking the keyboard (captures while someone works).
    public var isQuiet = false

    public init() {}

    public var isOpen: Bool { panel?.isVisible == true }

    /// Shows `content` under `anchor` (AppKit coordinates), centered on it and kept on its screen. With `mark`, the
    /// panel is a drawer that drops from its item in the menu bar, the way Col's island hangs from the notch: the item
    /// turns black with its mark in white, and the panel flows out of it. Without, it floats under the menu bar.
    public func show<Content: View>(_ content: Content, under anchor: CGRect, target: StatusItemsController.Target?) {
        showDrop(content, mark: EmptyView(), under: anchor, target: target, hangs: false)
    }

    /// A drawer dropping from its item in the menu bar, whose mark `mark` draws.
    public func showDrop<Content: View, Mark: View>(_ content: Content, mark: Mark, under anchor: CGRect,
                                                    target: StatusItemsController.Target?, hangs: Bool = true) {
        close(animated: false)
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main
        guard let screen else { return }
        let size = NSHostingView(rootView: content.environment(\.colorScheme, .dark)).fittingSize
        let room = Theme.panelShadowRoom
        let visible = screen.visibleFrame
        // From the top of the screen to the item's lower edge: the menu bar's height, which the neck fills.
        let neckHeight = hangs ? max(0, screen.frame.maxY - anchor.minY) : 0
        let gap: CGFloat = hangs ? 0 : 6
        var panelX = anchor.midX - size.width / 2
        panelX = min(max(panelX, visible.minX + 8), visible.maxX - size.width - 8)
        let left = min(panelX, hangs ? anchor.minX - DropShape.ear : panelX) - room
        let right = max(panelX + size.width, hangs ? anchor.maxX + DropShape.ear : panelX) + room
        let top = hangs ? screen.frame.maxY : anchor.minY - gap
        let height = (hangs ? neckHeight : 0) + size.height + room * 1.6
        let frame = CGRect(x: left, y: max(top - height, visible.minY - room), width: right - left, height: height)
        let neck = hangs ? CGRect(x: anchor.minX - left, y: 0, width: anchor.width, height: neckHeight) : .zero
        let panelRect = CGRect(x: panelX - left, y: hangs ? neckHeight : 0, width: size.width, height: size.height)
        let state = DropState()
        let panel = FloatingPanel()
        let hosting = NSHostingView(rootView: DropPanel(neck: neck, panel: panelRect, size: frame.size, mark: mark, content: content,
                                                        state: state))
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = hosting
        panel.setFrame(frame, display: true)
        panel.onClose = { [weak self] in self?.close() }
        self.panel = panel
        self.state = state
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
        close(animated: true)
    }

    /// Closes the open panel: the drawer goes back into its item, then its window goes.
    public func close(animated: Bool) {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer); NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        openTarget = nil
        isSearchOpen = false
        guard let panel else { return }
        self.panel = nil
        let state = self.state
        self.state = nil
        guard animated, let state, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            return
        }
        panel.ignoresMouseEvents = true
        withAnimation(.spring(response: 0.26, dampingFraction: 1)) { state.progress = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { panel.orderOut(nil) }
    }

    /// The drop is laid out for its content once, as it opens: a filter that changes the drawer's icons scrolls within
    /// it rather than resizing the window.
    public func fitToContent() {}

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
