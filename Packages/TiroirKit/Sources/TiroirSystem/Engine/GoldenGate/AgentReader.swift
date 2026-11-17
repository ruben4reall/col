import AppKit
import ApplicationServices
import os

/// What MenuBarAgent draws on macOS 27, read over Accessibility (spec 4.4, Discovery).
///
/// MenuBarAgent has one window per display; each child is a slot holding one icon. A slot's child belongs to the app
/// that draws the icon, or to MenuBarAgent itself for a system item such as the clock. The `«` button, which macOS
/// shows when icons do not fit beside the notch, is the one slot without a child. Icons that do not fit keep a frame,
/// stacked at the left of the region: they are not drawn.
@available(macOS 26, *)
public struct AgentLayout: Sendable {
    public struct Item: Sendable {
        public var bundleID: String?
        public var systemIdentifier: String?
        public var frame: CGRect
        public var pid: pid_t
        public var element: AXElement?
        public var isOverflowButton: Bool
        /// The app's own words for the icon, and its identifier when it gives one.
        public var label: String? = nil
        public var identifier: String? = nil
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

@available(macOS 26, *)
public enum AgentReader {
    public static let agentBundleID = "com.apple.MenuBarAgent"

    /// Apps whose icon did not answer in time, and when: they are not asked again for `backoff` seconds, the way
    /// `ExtrasReader` leaves them alone.
    static let unresponsive = OSAllocatedUnfairLock(initialState: [pid_t: Date]())
    static let backoff: TimeInterval = 30

    /// Reads MenuBarAgent, or nil when it is not running (macOS 26) or refuses (no Accessibility). Every question,
    /// to MenuBarAgent or to an app whose icon it holds, waits `timeout` seconds at most, and an app that did not answer
    /// is left alone for half a minute: a read stays short even when an app hangs. Without `labels`, only MenuBarAgent
    /// and each app's kind of element are asked, never the icons' words. It asks other processes and waits for them:
    /// call it off the main thread, as `readInBackground` does.
    public static func read(timeout: Float = 0.25, labels: Bool = true) -> AgentLayout? {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: agentBundleID).first else { return nil }
        let agentPID = agent.processIdentifier
        let application = AXElement.application(agentPID, timeout: timeout)
        let windows = application.elements(kAXWindowsAttribute)
        guard !windows.isEmpty else { return nil }
        let now = Date()
        let skipped = unresponsive.withLock { state in
            state = state.filter { now.timeIntervalSince($0.value) < backoff }
            return Set(state.keys)
        }

        struct Slot {
            var frame: CGRect
            var element: AXElement
            var owner: AXElement?
            var ownerPID: pid_t
            /// The owner's kind: an app's live button on the bar on screen, its application element elsewhere.
            var ownerRole: String?
        }
        let read = windows.map { window -> (frame: CGRect?, slots: [Slot]) in
            let slots = window.children.compactMap { element -> Slot? in
                guard let frame = element.frame else { return nil }
                let owner = element.children.first
                let pid = owner?.pid ?? agentPID
                var role: String?
                if let owner, pid == agentPID || !skipped.contains(pid) {
                    var value: CFTypeRef?
                    let error = AXUIElementCopyAttributeValue(owner.raw, kAXRoleAttribute as CFString, &value)
                    role = value as? String
                    if error == .cannotComplete, pid != agentPID {
                        unresponsive.withLock { $0[pid] = Date() }
                        Log.accessibility.debug("the icon of pid \(pid) did not answer in time")
                    }
                }
                return Slot(frame: frame, element: element, owner: owner, ownerPID: pid, ownerRole: role)
            }
            return (window.frame, slots)
        }
        let silent = unresponsive.withLock { Set($0.keys) }
        let chosen = chooseBars(read.map { window in
            (window.frame, window.slots.filter { $0.ownerRole != nil && $0.ownerRole != kAXApplicationRole }.count)
        })
        let displays = chosen.map { index -> AgentLayout.Display in
            let items = read[index].slots.compactMap { slot -> AgentLayout.Item? in
                guard let owner = slot.owner else {
                    guard slot.element.role == kAXButtonRole else { return nil }
                    return AgentLayout.Item(bundleID: nil, systemIdentifier: nil, frame: slot.frame, pid: agentPID, element: slot.element,
                                            isOverflowButton: true)
                }
                if slot.ownerPID == agentPID {
                    let identifier = labels ? (owner.children.first?.identifier ?? owner.identifier) : nil
                    return AgentLayout.Item(bundleID: nil, systemIdentifier: identifier, frame: slot.frame, pid: agentPID, element: owner,
                                            isOverflowButton: false)
                }
                let bundleID = NSRunningApplication(processIdentifier: slot.ownerPID)?.bundleIdentifier
                guard labels, !silent.contains(slot.ownerPID) else {
                    return AgentLayout.Item(bundleID: bundleID, systemIdentifier: nil, frame: slot.frame, pid: slot.ownerPID, element: owner,
                                            isOverflowButton: false)
                }
                let label = [owner.descriptionText, owner.title, owner.help]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty }
                return AgentLayout.Item(bundleID: bundleID, systemIdentifier: nil, frame: slot.frame, pid: slot.ownerPID, element: owner,
                                        isOverflowButton: false, label: label, identifier: owner.identifier)
            }
            return AgentLayout.Display(frame: read[index].frame ?? .zero, items: items)
        }
        return AgentLayout(displays: displays, agentPID: agentPID)
    }

    /// `read`, on a thread of its own: the caller waits without holding the main thread.
    public static func readInBackground(timeout: Float = 0.25, labels: Bool = true) async -> AgentLayout? {
        await Task.detached(priority: .userInitiated) { read(timeout: timeout, labels: labels) }.value
    }

    /// One bar per display. macOS 27.2 keeps several windows over the same display (three on a MacBook Pro with one
    /// screen, all with the menu bar's frame): the one on screen holds the apps' live buttons, the others stand-ins for
    /// the apps (their application element), and which one is on screen changes. Of windows with the same frame, the
    /// one with the most live buttons wins; on a tie, the first. Returns the indices of the windows kept, from each
    /// window's frame and count of live buttons.
    static func chooseBars(_ windows: [(frame: CGRect?, live: Int)]) -> [Int] {
        var chosen: [(frame: CGRect, index: Int, live: Int)] = []
        for (index, window) in windows.enumerated() {
            guard let frame = window.frame else { continue }
            if let existing = chosen.firstIndex(where: { $0.frame == frame }) {
                if window.live > chosen[existing].live { chosen[existing] = (frame, index, window.live) }
            } else {
                chosen.append((frame, index, window.live))
            }
        }
        return chosen.map(\.index)
    }

    /// Reads until two reads in a row agree: MenuBarAgent keeps moving icons for a moment after a restriction changes.
    /// With `previous`, the layout must first differ from it, since a new restriction takes a moment to land.
    public static func readSettled(after previous: AgentLayout? = nil, attempts: Int = 8, interval: Duration = .milliseconds(120)) async -> AgentLayout? {
        var last: AgentLayout?
        var changed = previous == nil
        for _ in 0..<attempts {
            try? await Task.sleep(for: interval)
            guard let now = await readInBackground() else { continue }
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
