import CoreGraphics

/// The prompter's outline: a body hanging from the top edge of the screen, with concave ears where it meets it and
/// rounded lower corners.
public struct PrompterShape: Equatable, Sendable {
    /// Width of the body, ears excluded.
    public var width: CGFloat
    public var height: CGFloat
    public var earRadius: CGFloat
    public var cornerRadius: CGFloat

    public init(width: CGFloat, height: CGFloat, earRadius: CGFloat, cornerRadius: CGFloat) {
        self.width = width
        self.height = height
        self.earRadius = earRadius
        self.cornerRadius = cornerRadius
    }

    /// Width including both ears.
    public var outerWidth: CGFloat { width + earRadius * 2 }
}

/// Every size the notch prompter takes on one screen, in a top-left canvas big enough for all of them. The canvas
/// starts at the top of the screen: the prompter grows out of the camera housing, and on a screen without a notch it
/// drops from the same place, over the middle of the menu bar.
public struct PrompterLayout: Equatable, Sendable {
    public let notch: NotchMetrics
    /// Width of the open prompter.
    public let width: CGFloat
    /// Height of the text area below the camera.
    public let textHeight: CGFloat

    /// Room around the open prompter for the halo of light beneath it.
    static let shadowMargin: CGFloat = 24
    /// Room left and right of the camera for the timer and the voice.
    static let wingMinimum: CGFloat = 95
    /// The classic notch prompter's proportions: ears of 25 points and lower corners of 13 on a body 400 points wide.
    static let earRatio: CGFloat = 25 / 400
    static let cornerRatio: CGFloat = 13 / 400

    public init(notch: NotchMetrics, width: CGFloat, textHeight: CGFloat) {
        self.notch = notch
        self.width = width
        self.textHeight = textHeight
    }

    /// Closed, the camera housing itself (a sliver at the top edge without a notch); open, the prompter around it,
    /// with a row as tall as the notch or the menu bar above the text.
    public func shape(open: Bool) -> PrompterShape {
        guard open else {
            return notch.isHardware
                ? PrompterShape(width: notch.width, height: notch.height, earRadius: 4, cornerRadius: 9)
                : PrompterShape(width: notch.width, height: 6, earRadius: 2, cornerRadius: 3)
        }
        let body = max(width, notch.width + Self.wingMinimum * 2)
        return PrompterShape(width: body, height: notch.height + textHeight, earRadius: body * Self.earRatio, cornerRadius: body * Self.cornerRatio)
    }

    public var canvasSize: CGSize {
        let open = shape(open: true)
        return CGSize(width: open.outerWidth + Self.shadowMargin * 2, height: open.height + Self.shadowMargin)
    }

    /// The body of the open prompter, ears excluded, in the canvas, top-left origin.
    public var bodyFrame: CGRect {
        let open = shape(open: true)
        return CGRect(x: (canvasSize.width - open.width) / 2, y: 0, width: open.width, height: open.height)
    }

    /// The camera row, left and right of the notch: the timer on one side, the voice on the other.
    public var wingFrames: (left: CGRect, right: CGRect) {
        let body = bodyFrame
        let side = (body.width - notch.width) / 2
        return (CGRect(x: body.minX, y: 0, width: side, height: notch.height),
                CGRect(x: body.maxX - side, y: 0, width: side, height: notch.height))
    }

    /// The text area, right under the camera.
    public var textFrame: CGRect {
        CGRect(x: bodyFrame.minX, y: notch.height, width: bodyFrame.width, height: textHeight)
    }
}

public enum PrompterPath {
    /// The outline in a top-left space: the top edge lies on y = 0 and the body is centred on `centerX`. Every shape
    /// is built from the same sequence of segments, so Core Animation can morph one into another. The lower corners
    /// ease into the straight edges (continuous curvature), softer than a circular arc.
    public static func make(_ shape: PrompterShape, centerX: CGFloat) -> CGPath {
        let ear = max(0, min(shape.earRadius, shape.height / 3))
        let left = centerX - shape.width / 2
        let right = centerX + shape.width / 2
        let bottom = shape.height
        let radius = min(shape.cornerRadius, shape.height / 2, shape.width / 2)
        let reach = max(0, min(radius * smoothing, bottom - ear, shape.width / 2))
        let handle = reach * handleRatio

        let path = CGMutablePath()
        path.move(to: CGPoint(x: left - ear, y: 0))
        path.addQuadCurve(to: CGPoint(x: left, y: ear), control: CGPoint(x: left, y: 0))
        path.addLine(to: CGPoint(x: left, y: bottom - reach))
        path.addCurve(to: CGPoint(x: left + reach, y: bottom), control1: CGPoint(x: left, y: bottom - handle), control2: CGPoint(x: left + handle, y: bottom))
        path.addLine(to: CGPoint(x: right - reach, y: bottom))
        path.addCurve(to: CGPoint(x: right, y: bottom - reach), control1: CGPoint(x: right - handle, y: bottom), control2: CGPoint(x: right, y: bottom - handle))
        path.addLine(to: CGPoint(x: right, y: ear))
        path.addQuadCurve(to: CGPoint(x: right + ear, y: 0), control: CGPoint(x: right, y: 0))
        path.closeSubpath()
        return path
    }

    /// A continuous corner spreads over more of each edge than a circular arc of the same radius.
    static let smoothing: CGFloat = 1.28
    /// Distance of the Bézier handles from the corner, as a share of the reach. A circle would sit at 0.448.
    static let handleRatio: CGFloat = 0.36
}
