import AppKit
import ApplicationServices
import TiroirSystem

/// Where the menu bar's items are, so the island's wings never cover them. Coordinates are global, top-left, as
/// Accessibility and the window server use.
@MainActor
enum MenuBarSpace {
    /// Since macOS 27 every status item, and the chevron that shows the hidden ones, is drawn by this one process.
    nonisolated static let menuBarAgentID = "com.apple.MenuBarAgent"

    static var menuBarAgent: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: menuBarAgentID).first
    }

    /// Col's own items in the menu bar (the drawers, when the menu bar option is on), in AppKit coordinates. Before
    /// macOS 27 each app draws its own items, and Col does not ask itself over Accessibility: it says where they are.
    static var ownItems: @MainActor () -> [CGRect] = { [] }

    /// Where the frontmost app's menus end on each side of the notch. With many menus macOS moves the last ones to
    /// the right of the notch, so both sides can hold menus. Needs Accessibility; nil without it, or when the menus
    /// cannot be read.
    ///
    /// The menus are those of the app that owns the menu bar, which is not always the frontmost one: an alert agent
    /// such as UserNotificationCenter can come to the front with no menus of its own while the previous app's stay.
    static func appMenus(notchCenter: CGFloat) -> (leftEnd: CGFloat?, rightStart: CGFloat?)? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.menuBarOwningApplication ?? NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.1)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &bar) == .success, let bar else { return nil }
        var leftEnd: CGFloat?, rightStart: CGFloat?
        // swiftlint:disable:next force_cast
        let menuBar = bar as! AXUIElement
        // The timeout holds only for the element it is set on: the bar and each menu get their own.
        AXUIElementSetMessagingTimeout(menuBar, 0.1)
        for item in children(of: menuBar) {
            AXUIElementSetMessagingTimeout(item, 0.1)
            guard let frame = frame(of: item), frame.width > 0 else { continue }
            if frame.midX < notchCenter {
                leftEnd = max(leftEnd ?? frame.maxX, frame.maxX)
            } else {
                rightStart = min(rightStart ?? frame.minX, frame.minX)
            }
        }
        return (leftEnd, rightStart)
    }

    /// The left edge of the first status item to the right of `x`, on the menu bar whose top is at `top` and which
    /// spans `span` (several screens each have a menu bar). Read through the extras menu bar with Accessibility; nil
    /// without it.
    ///
    /// On macOS 27 and later MenuBarAgent holds them all, so it alone is asked. Before, each app drew its own and
    /// every running app is asked.
    static func statusItemsLeftEdge(after x: CGFloat, top: CGFloat, span: ClosedRange<CGFloat>) -> CGFloat? {
        guard AXIsProcessTrusted() else { return nil }
        let owners: [NSRunningApplication]
        if let agent = menuBarAgent, !extras(of: agent.processIdentifier).isEmpty {
            owners = [agent]
        } else {
            let me = ProcessInfo.processInfo.processIdentifier
            owners = NSWorkspace.shared.runningApplications.filter { $0.processIdentifier != me }
        }
        var edge: CGFloat?
        for app in owners {
            for item in extras(of: app.processIdentifier) {
                guard let frame = frame(of: item), frame.width > 0, frame.minX > x,
                      span.contains(frame.minX), abs(frame.minY - top) < 4
                else { continue }
                edge = min(edge ?? frame.minX, frame.minX)
            }
        }
        // macOS 27.2 describes only Apple's own items in MenuBarAgent's extras menu bar: every other app's icon, and
        // Col's drawers, show only in its windows, one slot per icon. Those are read in the background (see `agentBars`):
        // the island uses the last read, and measures again when a new one differs.
        if owners.first?.bundleIdentifier == menuBarAgentID {
            if let bars = agentBars, let drawn = drawnLeftEdge(of: bars, after: x, top: top, span: span) { edge = min(edge ?? drawn, drawn) }
            readAgentBars()
        }
        // Since macOS 27 MenuBarAgent draws Col's items too; before, they are Col's own windows.
        if owners.first?.bundleIdentifier != menuBarAgentID {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            for item in ownItems() {
                // AppKit measures from the bottom left of the main screen, Accessibility from its top left.
                let itemTop = primaryHeight - item.maxY
                guard item.minX > x, span.contains(item.minX), abs(itemTop - top) < 4 else { continue }
                edge = min(edge ?? item.minX, item.minX)
            }
        }
        return edge
    }

    /// The left edge of the first icon MenuBarAgent draws right of `x` on the bar whose top is at `top`: icons that do
    /// not fit beside the notch wait undrawn, stacked left of the » button, which is drawn.
    nonisolated static func drawnLeftEdge(of bars: [AgentBar], after x: CGFloat, top: CGFloat, span: ClosedRange<CGFloat>) -> CGFloat? {
        var edge: CGFloat?
        for bar in bars where abs(bar.frame.minY - top) < 4 && span.contains(bar.frame.midX) {
            let overflow = bar.slots.first(where: \.isOverflow)?.frame.minX
            for slot in bar.slots where slot.frame.width > 0 {
                let minX = slot.frame.minX
                if let overflow, !slot.isOverflow, minX < overflow { continue }
                // Stacked on another icon: waiting undrawn, as when it does not fit or MenuBarAgent is still laying the
                // bar out. The same test as the drawers' own.
                let stacked = !slot.isOverflow && bar.slots.contains { other in
                    other != slot && !other.isOverflow && other.frame.intersection(slot.frame).width > 2
                }
                guard !stacked, minX > x, span.contains(minX) else { continue }
                edge = min(edge ?? minX, minX)
            }
        }
        return edge
    }

    /// One of MenuBarAgent's bars, as the island needs it: where each slot is, and which one is the » button.
    struct AgentBar: Equatable, Sendable {
        struct Slot: Equatable, Sendable {
            var frame: CGRect
            var isOverflow: Bool
        }

        var frame: CGRect
        var slots: [Slot]
    }

    /// MenuBarAgent's bars at the last read, nil before the first one.
    private(set) static var agentBars: [AgentBar]?
    private static var readingAgentBars = false
    /// The island measures again when a read finds the bars changed.
    static var agentBarsChanged: (@MainActor () -> Void)?

    /// Reads MenuBarAgent's bars on a thread of their own, one read at a time: MenuBarAgent and the apps whose icons
    /// it holds are asked over Accessibility, and one that stops answering must never hold the island. Each question
    /// waits a quarter of a second at most, an app that did not answer is left alone for half a minute, and the icons'
    /// words are never asked.
    static func readAgentBars() {
        guard #available(macOS 26, *), !readingAgentBars else { return }
        readingAgentBars = true
        Task {
            let layout = await AgentReader.readInBackground(labels: false)
            readingAgentBars = false
            let bars = layout.map { layout in
                layout.displays.map { display in
                    AgentBar(frame: display.frame, slots: display.items.map { AgentBar.Slot(frame: $0.frame, isOverflow: $0.isOverflowButton) })
                }
            }
            guard bars != agentBars else { return }
            agentBars = bars
            agentBarsChanged?()
        }
    }

    /// The items of an app's extras menu bar, its status items.
    private static func extras(of pid: pid_t) -> [AXUIElement] {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.05)
        var extras: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &extras) == .success, let extras else { return [] }
        // swiftlint:disable:next force_cast
        let bar = extras as! AXUIElement
        // A timeout holds only for the element it is set on: the bar and each item get their own, so an app that
        // stops answering costs a twentieth of a second per question, not six seconds.
        AXUIElementSetMessagingTimeout(bar, 0.05)
        let items = children(of: bar)
        for item in items { AXUIElementSetMessagingTimeout(item, 0.05) }
        return items
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success else { return [] }
        return children as? [AXUIElement] ?? []
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size
        else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        // swiftlint:disable force_cast
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        // swiftlint:enable force_cast
        return CGRect(origin: point, size: extent)
    }
}

/// Tells when a status item comes, goes or changes width, so the wings are measured again then and only then.
///
/// On macOS 27 MenuBarAgent draws every status item and reports these changes through Accessibility, including its
/// chevron for hidden items, which comes and goes by itself right beside the notch. Earlier systems have no single
/// owner to watch; apps launching and quitting stand in for it there.
@MainActor
final class MenuBarWatcher {
    var onChange: (() -> Void)?
    private var observer: AXObserver?
    private var watched: pid_t = 0
    private var pending: Task<Void, Never>?
    private var relaunch: NSObjectProtocol?

    /// Starts watching, or watches again after MenuBarAgent restarted or Accessibility was granted.
    func start() {
        if relaunch == nil {
            relaunch = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                guard (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == MenuBarSpace.menuBarAgentID
                else { return }
                MainActor.assumeIsolated {
                    self?.attach()
                    self?.changed()
                }
            }
        }
        attach()
    }

    private func attach() {
        guard AXIsProcessTrusted(), let agent = MenuBarSpace.menuBarAgent else { return }
        let pid = agent.processIdentifier
        guard observer == nil || pid != watched else { return }
        detach()
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<MenuBarWatcher>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.changed() }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var any = false
        for name in [kAXLayoutChangedNotification, kAXCreatedNotification, kAXUIElementDestroyedNotification] {
            any = AXObserverAddNotification(created, element, name as CFString, refcon) == .success || any
        }
        guard any else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        watched = pid
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        watched = 0
    }

    /// Changes come in bursts (an item added reports several layouts): measure once they have settled.
    private func changed() {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }
}
