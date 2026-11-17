import CoreGraphics
import Foundation

/// Pairs the icons Accessibility describes with the windows that draw them (macOS 26).
///
/// On macOS 26 Control Center owns every icon's window, so the window list no longer says which app an icon belongs
/// to; Accessibility does, with a frame. The frames agree within a point or two, but not always in width (Proton Mail
/// Bridge's element is narrower than its window), so an element belongs to the window that contains its middle.
public enum FrameMatcher {
    public struct Element: Sendable, Equatable {
        public var index: Int
        public var frame: CGRect
        public init(index: Int, frame: CGRect) {
            self.index = index
            self.frame = frame
        }
    }

    public struct Window: Sendable, Equatable {
        public var id: UInt32
        public var frame: CGRect
        public init(id: UInt32, frame: CGRect) {
            self.id = id
            self.frame = frame
        }
    }

    /// Element index to window identifier. Each window goes to at most one element, the nearest by middles, and an
    /// element whose middle lies in no window (give or take `tolerance` points) stays unmatched.
    public static func match(elements: [Element], windows: [Window], tolerance: CGFloat = 3) -> [Int: UInt32] {
        var pairs: [(element: Int, window: UInt32, distance: CGFloat)] = []
        for element in elements where element.frame.width > 0 {
            let middle = CGPoint(x: element.frame.midX, y: element.frame.midY)
            for window in windows {
                let slack = window.frame.insetBy(dx: -tolerance, dy: -tolerance)
                guard middle.x >= slack.minX, middle.x <= slack.maxX,
                      middle.y >= slack.minY, middle.y <= slack.maxY else { continue }
                pairs.append((element.index, window.id, abs(middle.x - window.frame.midX)))
            }
        }
        var result: [Int: UInt32] = [:]
        var takenWindows = Set<UInt32>()
        for pair in pairs.sorted(by: { $0.distance < $1.distance }) {
            guard result[pair.element] == nil, !takenWindows.contains(pair.window) else { continue }
            result[pair.element] = pair.window
            takenWindows.insert(pair.window)
        }
        return result
    }
}
