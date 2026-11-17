import AppKit
import CoreGraphics

/// Where a Command-drag can drop an icon on macOS 26 (spec 4.3, Arranging). macOS places no icon under the notch, and
/// apps drawn around it keep windows over the menu bar, or right under it, that catch the pointer when it comes near:
/// a drop there lands anywhere. A drop is safe right of both, with room for their hover areas.
@MainActor
public enum DropZone {
    /// Room kept right of the notch: drops closer than this failed on a MacBook Pro whose notch apps widen on hover.
    nonisolated static let notchMargin: CGFloat = 80
    /// Room kept right of a window another app draws over the menu bar.
    nonisolated static let overlayMargin: CGFloat = 40

    private static var cached: (start: CGFloat, at: ContinuousClock.Instant)?

    /// Whether a drop at `x` (window server coordinates, main display) is safe.
    public static func isSafe(_ x: CGFloat) -> Bool {
        x >= safeStart()
    }

    /// The leftmost safe x, read at most once a second: windows come and go.
    static func safeStart() -> CGFloat {
        if let cached, ContinuousClock.now - cached.at < .seconds(1) { return cached.start }
        let start = measure()
        cached = (start, .now)
        return start
    }

    private static func measure() -> CGFloat {
        guard let screen = NSScreen.screens.first else { return 0 }
        var start: CGFloat = 0
        if let right = screen.auxiliaryTopRightArea {
            start = right.minX - screen.frame.minX + notchMargin
        }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let windows = list.compactMap { info -> Overlay? in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let owner = info[kCGWindowOwnerPID as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return Overlay(layer: layer, frame: frame, ownerPID: pid_t(owner))
        }
        let barHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return max(start, overlayStart(windows, barHeight: barHeight, screenWidth: screen.frame.width,
                                       ownPID: ProcessInfo.processInfo.processIdentifier))
    }

    struct Overlay: Equatable, Sendable {
        var layer: Int
        var frame: CGRect
        var ownerPID: pid_t
    }

    /// Right of every window another app keeps over the menu bar or right under it, above the icons' level and below
    /// the menus'. A window across the whole screen is no island around the notch, and does not count.
    nonisolated static func overlayStart(_ windows: [Overlay], barHeight: CGFloat, screenWidth: CGFloat,
                                         ownPID: pid_t) -> CGFloat {
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return windows
            .filter { window in
                window.layer > statusLevel && window.layer < menuLevel - 1 && window.ownerPID != ownPID
                    && window.frame.minY < barHeight + 4 && window.frame.maxY > 0
                    && window.frame.minX < screenWidth && window.frame.maxX > 0
                    && window.frame.width < screenWidth * 0.9
            }
            .map { $0.frame.maxX + overlayMargin }
            .max() ?? 0
    }
}
