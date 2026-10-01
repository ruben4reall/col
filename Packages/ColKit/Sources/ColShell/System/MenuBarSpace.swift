import AppKit
import ApplicationServices

/// Where the menu bar's items are, so the island's wings never cover them. Coordinates are global, top-left, as
/// Accessibility and the window server use.
@MainActor
enum MenuBarSpace {
    /// Where the frontmost app's menus end on each side of the notch. With many menus macOS moves the last ones to
    /// the right of the notch, so both sides can hold menus. Needs Accessibility; nil without it.
    static func appMenus(notchCenter: CGFloat) -> (leftEnd: CGFloat?, rightStart: CGFloat?)? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &bar) == .success, let bar else { return nil }
        var children: CFTypeRef?
        // swiftlint:disable:next force_cast
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement]
        else { return nil }
        var leftEnd: CGFloat?, rightStart: CGFloat?
        for item in items {
            guard let frame = frame(of: item), frame.width > 0 else { continue }
            if frame.midX < notchCenter {
                leftEnd = max(leftEnd ?? frame.maxX, frame.maxX)
            } else {
                rightStart = min(rightStart ?? frame.minX, frame.minX)
            }
        }
        return (leftEnd, rightStart)
    }

    /// The left edge of the first status item to the right of `x`. macOS draws status items inside the menu bar,
    /// so they are read through each app's extras menu bar, with Accessibility; nil without it.
    static func statusItemsLeftEdge(after x: CGFloat) -> CGFloat? {
        guard AXIsProcessTrusted() else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        var edge: CGFloat?
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != me {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.05)
            var extras: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &extras) == .success, let extras else { continue }
            var children: CFTypeRef?
            // swiftlint:disable:next force_cast
            guard AXUIElementCopyAttributeValue(extras as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
                  let items = children as? [AXUIElement]
            else { continue }
            for item in items {
                guard let frame = frame(of: item), frame.width > 0, frame.minX > x else { continue }
                edge = min(edge ?? frame.minX, frame.minX)
            }
        }
        return edge
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
