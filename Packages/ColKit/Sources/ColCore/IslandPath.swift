import CoreGraphics

public enum IslandPath {
    /// The island's outline in a top-left space: the top edge lies on y = 0 and the body is centred on `centerX`.
    ///
    /// Every shape is built from the same sequence of segments, so Core Animation can morph one into another.
    /// The lower corners use a curve that eases into the straight edges (continuous curvature), which reads softer
    /// than a circular arc at the same radius.
    public static func make(_ shape: IslandShape, centerX: CGFloat) -> CGPath {
        if shape.isFloating { return floating(shape, centerX: centerX) }
        let ear = max(0, min(shape.earRadius, shape.height / 3))
        let left = centerX - shape.width / 2
        let right = centerX + shape.width / 2
        let bottom = shape.height
        // How far the corner reaches along each edge, kept inside the straight part of the body.
        let reach = max(0, min(shape.cornerRadius * smoothing, (bottom - ear), shape.width / 2))
        let handle = reach * handleRatio

        let path = CGMutablePath()
        path.move(to: CGPoint(x: left - ear, y: 0))
        path.addQuadCurve(to: CGPoint(x: left, y: ear), control: CGPoint(x: left, y: 0))
        path.addLine(to: CGPoint(x: left, y: bottom - reach))
        path.addCurve(
            to: CGPoint(x: left + reach, y: bottom),
            control1: CGPoint(x: left, y: bottom - handle),
            control2: CGPoint(x: left + handle, y: bottom)
        )
        path.addLine(to: CGPoint(x: right - reach, y: bottom))
        path.addCurve(
            to: CGPoint(x: right, y: bottom - reach),
            control1: CGPoint(x: right - handle, y: bottom),
            control2: CGPoint(x: right, y: bottom - handle)
        )
        path.addLine(to: CGPoint(x: right, y: ear))
        path.addQuadCurve(to: CGPoint(x: right + ear, y: 0), control: CGPoint(x: right, y: 0))
        path.closeSubpath()
        return path
    }

    /// The floating island: rounded on all four corners, drawn with the same kinds of segments as the attached one.
    private static func floating(_ shape: IslandShape, centerX: CGFloat) -> CGPath {
        let left = centerX - shape.width / 2, right = centerX + shape.width / 2
        let top = shape.gap, bottom = shape.gap + shape.height
        let radius = min(shape.cornerRadius, shape.height / 2, shape.width / 2)
        let reach = min(radius * smoothing, shape.height / 2, shape.width / 2)
        let handle = reach * handleRatio
        let path = CGMutablePath()
        path.move(to: CGPoint(x: left + reach, y: top))
        path.addQuadCurve(to: CGPoint(x: left, y: top + reach), control: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left, y: bottom - reach))
        path.addCurve(to: CGPoint(x: left + reach, y: bottom), control1: CGPoint(x: left, y: bottom - handle), control2: CGPoint(x: left + handle, y: bottom))
        path.addLine(to: CGPoint(x: right - reach, y: bottom))
        path.addCurve(to: CGPoint(x: right, y: bottom - reach), control1: CGPoint(x: right - handle, y: bottom), control2: CGPoint(x: right, y: bottom - handle))
        path.addLine(to: CGPoint(x: right, y: top + reach))
        path.addQuadCurve(to: CGPoint(x: right - reach, y: top), control: CGPoint(x: right, y: top))
        path.closeSubpath()
        return path
    }

    /// A continuous corner spreads over more of each edge than a circular arc of the same radius.
    static let smoothing: CGFloat = 1.28
    /// Distance of the Bézier handles from the corner, as a share of the reach. A circle would sit at 0.448.
    static let handleRatio: CGFloat = 0.36
}
