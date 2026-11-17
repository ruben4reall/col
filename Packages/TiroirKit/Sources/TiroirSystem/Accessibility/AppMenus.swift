import ApplicationServices
import CoreGraphics

/// An app's menus in the menu bar (the Apple menu, its own menu, File, Edit…), as Accessibility describes them. The
/// split shape of the tint ends its left piece where the front app's menus end.
public enum AppMenus {
    /// The frames of the app's menu bar items, in window server coordinates. Empty when the app has no menus, does not
    /// answer in time, or Accessibility is off. Every read is a round trip to the app, capped by `timeout`: call it
    /// away from the main actor.
    public static func frames(of pid: pid_t, timeout: Float = 0.2) -> [CGRect] {
        guard let bar = AXElement.application(pid, timeout: timeout).element(kAXMenuBarAttribute) else { return [] }
        AXUIElementSetMessagingTimeout(bar.raw, timeout)
        return bar.children.compactMap { item in
            AXUIElementSetMessagingTimeout(item.raw, timeout)
            guard let frame = item.frame, frame.width > 0, frame.height > 0 else { return nil }
            return frame
        }
    }
}
