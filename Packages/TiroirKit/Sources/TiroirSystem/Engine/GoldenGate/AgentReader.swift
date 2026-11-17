import AppKit
import ApplicationServices

/// What MenuBarAgent draws on macOS 27, read over Accessibility (spec 4.4, Discovery).
///
/// MenuBarAgent has one window per display; each child is a slot holding one icon. A slot's child belongs to the app
/// that draws the icon, or to MenuBarAgent itself for a system item such as the clock. The `«` button, which macOS
/// shows when icons do not fit beside the notch, is the one slot without a child. Icons that do not fit keep a frame,
/// stacked at the left of the region: they are not drawn.
public struct AgentLayout: Sendable {
    public struct Item: Sendable {
        public var bundleID: String?
        public var systemIdentifier: String?
        public var frame: CGRect
        public var pid: pid_t
        public var element: AXElement?
        public var isOverflowButton: Bool
    }

    public struct Display: Sendable {
        public var frame: CGRect
        public var items: [Item]
    }

    public var displays: [Display]
    public var agentPID: pid_t

    public static let clockIdentifier = "com.apple.menuextra.clock"

    /// The icon of `bundleID` when macOS really draws it: not stacked on another icon, not left of the `«` button.
    public func drawnItem(of bundleID: String) -> Item? {
        for display in displays {
            guard let item = display.items.first(where: { $0.bundleID == bundleID }) else { continue }
            let overlapped = display.items.contains { other in
                other.bundleID != bundleID && !other.isOverflowButton && other.frame.intersection(item.frame).width > 2
            }
            let overflow = display.items.first { $0.isOverflowButton }
            let collapsed = overflow.map { item.frame.minX < $0.frame.minX } ?? false
            return overlapped || collapsed ? nil : item
        }
        return nil
    }

    /// The clock, where Notification Center opens.
    public var clockFrame: CGRect? {
        displays.lazy.compactMap { $0.items.first { $0.systemIdentifier == Self.clockIdentifier }?.frame }.first
    }

    /// Whether two reads show the same icons at the same places.
    public func sameLayout(as other: AgentLayout) -> Bool {
        displays.count == other.displays.count && zip(displays, other.displays).allSatisfy { a, b in
            a.items.count == b.items.count && zip(a.items, b.items).allSatisfy {
                $0.bundleID == $1.bundleID && $0.systemIdentifier == $1.systemIdentifier && $0.frame == $1.frame
            }
        }
    }
}

public enum AgentReader {
    public static let agentBundleID = "com.apple.MenuBarAgent"

    /// Reads MenuBarAgent, or nil when it is not running (macOS 26) or refuses (no Accessibility).
    public static func read() -> AgentLayout? {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: agentBundleID).first else { return nil }
        let agentPID = agent.processIdentifier
        let application = AXElement.application(agentPID, timeout: 1)
        guard let windows: [AXUIElement] = application.attribute(kAXWindowsAttribute) else { return nil }
        let displays = windows.map(AXElement.init).map { window -> AgentLayout.Display in
            let items = window.children.compactMap { slot -> AgentLayout.Item? in
                guard let frame = slot.frame else { return nil }
                guard let owner = slot.children.first else {
                    guard slot.role == kAXButtonRole else { return nil }
                    return AgentLayout.Item(bundleID: nil, systemIdentifier: nil, frame: frame, pid: agentPID, element: slot, isOverflowButton: true)
                }
                let pid = owner.pid ?? agentPID
                if pid == agentPID {
                    let identifier = owner.children.first?.identifier ?? owner.identifier
                    return AgentLayout.Item(bundleID: nil, systemIdentifier: identifier, frame: frame, pid: pid, element: owner, isOverflowButton: false)
                }
                let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
                return AgentLayout.Item(bundleID: bundleID, systemIdentifier: nil, frame: frame, pid: pid, element: owner, isOverflowButton: false)
            }
            return AgentLayout.Display(frame: window.frame ?? .zero, items: items)
        }
        return AgentLayout(displays: displays, agentPID: agentPID)
    }

    /// Reads until two reads in a row agree: MenuBarAgent keeps moving icons for a moment after a restriction changes.
    /// With `previous`, the layout must first differ from it, since a new restriction takes a moment to land.
    public static func readSettled(after previous: AgentLayout? = nil, attempts: Int = 8, interval: Duration = .milliseconds(120)) async -> AgentLayout? {
        var last: AgentLayout?
        var changed = previous == nil
        for _ in 0..<attempts {
            try? await Task.sleep(for: interval)
            guard let now = read() else { continue }
            if !changed {
                changed = !(previous.map(now.sameLayout(as:)) ?? false)
                if !changed { continue }
            }
            if let last, now.sameLayout(as: last) { return now }
            last = now
        }
        return last
    }
}
