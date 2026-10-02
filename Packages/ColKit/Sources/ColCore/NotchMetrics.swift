import CoreGraphics

/// Where the camera housing sits at the top of a screen, in points.
public struct NotchMetrics: Equatable, Sendable {
    public var width: CGFloat
    public var height: CGFloat
    /// Horizontal centre of the notch, measured from the screen's left edge.
    public var centerX: CGFloat
    /// False when the screen has no notch and Col draws the whole island itself.
    public var isHardware: Bool

    public init(width: CGFloat, height: CGFloat, centerX: CGFloat, isHardware: Bool) {
        self.width = width
        self.height = height
        self.centerX = centerX
        self.isHardware = isHardware
    }

    static let fallbackWidth: CGFloat = 180
    static let fallbackHeight: CGFloat = 24

    /// Reads the notch from what `NSScreen` reports: the safe area's top inset and the two menu bar areas that flank
    /// the camera. A screen without a notch gets an island the size of a notch, centred in its menu bar.
    public static func resolve(
        screenWidth: CGFloat,
        safeAreaTop: CGFloat,
        leftAreaWidth: CGFloat?,
        rightAreaWidth: CGFloat?,
        menuBarHeight: CGFloat
    ) -> NotchMetrics {
        if safeAreaTop > 0, let left = leftAreaWidth, let right = rightAreaWidth {
            let width = screenWidth - left - right
            if width > 0 {
                return NotchMetrics(width: width, height: safeAreaTop, centerX: left + width / 2, isHardware: true)
            }
        }
        let height = menuBarHeight > 0 ? menuBarHeight : fallbackHeight
        return NotchMetrics(width: fallbackWidth, height: height, centerX: screenWidth / 2, isHardware: false)
    }
}
