import ApplicationServices
import CoreGraphics
import Foundation

/// An Accessibility element that may cross threads. The element is a token for another process: every call on it is
/// a round trip, capped by the messaging timeout so an app that stops answering never stalls Tiroir.
public struct AXElement: @unchecked Sendable {
    public let raw: AXUIElement

    public init(_ raw: AXUIElement) {
        self.raw = raw
    }

    public static func application(_ pid: pid_t, timeout: Float = 0.2) -> AXElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, timeout)
        return AXElement(element)
    }

    public static var systemWide: AXElement { AXElement(AXUIElementCreateSystemWide()) }

    public func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(raw, name as CFString, &value) == .success, let value else { return nil }
        return value as? T
    }

    public func element(_ name: String) -> AXElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(raw, name as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return AXElement(value as! AXUIElement) // checked by the type identifier above
    }

    public var children: [AXElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(raw, kAXChildrenAttribute as CFString, &value) == .success,
              let array = value as? [AnyObject] else { return [] }
        return array.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? AXElement(item as! AXUIElement) : nil
        }
    }

    public var position: CGPoint? {
        guard let value: AXValue = attributeValue(kAXPositionAttribute) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    public var size: CGSize? {
        guard let value: AXValue = attributeValue(kAXSizeAttribute) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    /// Screen coordinates with the origin at the top left of the main display.
    public var frame: CGRect? {
        guard let position, let size else { return nil }
        return CGRect(origin: position, size: size)
    }

    public var role: String? { attribute(kAXRoleAttribute) }
    public var identifier: String? { attribute(kAXIdentifierAttribute) }
    public var title: String? { attribute(kAXTitleAttribute) }
    public var descriptionText: String? { attribute(kAXDescriptionAttribute) }
    public var help: String? { attribute(kAXHelpAttribute) }

    public var pid: pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(raw, &pid) == .success ? pid : nil
    }

    /// Presses the element as a click would. Returns whether the app accepted the action (an app can accept it and do
    /// nothing, as for an icon parked off screen on macOS 26).
    @discardableResult
    public func press(timeout: Float = 1) -> Bool {
        AXUIElementSetMessagingTimeout(raw, timeout)
        return AXUIElementPerformAction(raw, kAXPressAction as CFString) == .success
    }

    private func attributeValue(_ name: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(raw, name as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue) // checked by the type identifier above
    }
}
