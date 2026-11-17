import AppKit
import QuartzCore
import SwiftUI
import TiroirCore

/// The Core Animation layers of the tint on one display: the fill, the hairline and the shadow, edge to edge or
/// following the rounded pieces of the floating and split shapes.
@MainActor
enum TintLayers {
    /// How far the shadow reaches below the menu bar.
    static let shadowHeight: CGFloat = 12
    static let hairline = NSColor.white.withAlphaComponent(0.18)

    /// The window a look needs: the menu bar, and below it the room for the shadow, which takes no click either.
    static func windowFrame(menuBar: CGRect, look: Appearance.Look) -> CGRect {
        let shadow = look.shadow ? shadowHeight : 0
        return CGRect(x: menuBar.minX, y: menuBar.minY - shadow, width: menuBar.width, height: menuBar.height + shadow)
    }

    /// Replaces the sublayers of `layer`, which covers `frame` on screen, with `look` drawn in `pieces`.
    static func draw(_ look: Appearance.Look, in pieces: TintGeometry.Pieces, frame: CGRect, scale: CGFloat, on layer: CALayer) {
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        let bounds = CGRect(origin: .zero, size: frame.size)
        var local = pieces
        local.rects = pieces.rects.map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) }
        guard let bar = local.rects.first else { return }
        let sublayers = local.shape == .full
            ? edgeToEdge(look, bar: bar, scale: scale)
            : rounded(look, pieces: local, bounds: bounds, scale: scale)
        for sublayer in sublayers {
            sublayer.contentsScale = scale
            sublayer.mask?.contentsScale = scale
            layer.addSublayer(sublayer)
        }
    }

    /// The full width: the tint over the whole bar, a hairline along its bottom, a shade fading below it.
    private static func edgeToEdge(_ look: Appearance.Look, bar: CGRect, scale: CGFloat) -> [CALayer] {
        var layers: [CALayer] = []
        if let fill = fill(look, over: bar) { layers.append(fill) }
        if look.border {
            let line = CALayer()
            line.frame = CGRect(x: bar.minX, y: bar.minY, width: bar.width, height: 1 / scale)
            line.backgroundColor = hairline.cgColor
            layers.append(line)
        }
        if look.shadow {
            let shade = CAGradientLayer()
            shade.frame = CGRect(x: bar.minX, y: bar.minY - shadowHeight, width: bar.width, height: shadowHeight)
            shade.colors = [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.withAlphaComponent(0.2).cgColor]
            shade.startPoint = CGPoint(x: 0.5, y: 0)
            shade.endPoint = CGPoint(x: 0.5, y: 1)
            layers.append(shade)
        }
        return layers
    }

    /// Rounded pieces: one fill across the menu bar cut to their outline, so a gradient runs on from one piece to the
    /// next, a hairline along that outline, and a shadow around it.
    private static func rounded(
        _ look: Appearance.Look, pieces: TintGeometry.Pieces, bounds: CGRect, scale: CGFloat
    ) -> [CALayer] {
        let outline = pieces.outline().cgPath
        var layers: [CALayer] = []
        if look.shadow { layers.append(shadow(around: outline, bounds: bounds)) }
        if let fill = fill(look, over: bounds) {
            let cut = CAShapeLayer()
            cut.frame = bounds
            cut.path = outline
            fill.mask = cut
            layers.append(fill)
        }
        if look.border {
            // Inside the edge, as the full width's hairline lies inside the bar.
            let line = CAShapeLayer()
            line.frame = bounds
            line.path = pieces.outline(inset: 0.5 / scale).cgPath
            line.fillColor = nil
            line.strokeColor = hairline.cgColor
            line.lineWidth = 1 / scale
            layers.append(line)
        }
        return layers
    }

    /// The tint over `rect`: a color, or a gradient from left to right; nil without a tint.
    private static func fill(_ look: Appearance.Look, over rect: CGRect) -> CALayer? {
        switch look.tint {
        case .none:
            return nil
        case .color:
            let layer = CALayer()
            layer.frame = rect
            layer.backgroundColor = NSColor(look.color).withAlphaComponent(look.opacity).cgColor
            return layer
        case .gradient:
            let layer = CAGradientLayer()
            layer.frame = rect
            layer.startPoint = CGPoint(x: 0, y: 0.5)
            layer.endPoint = CGPoint(x: 1, y: 0.5)
            layer.colors = [
                NSColor(look.color).withAlphaComponent(look.opacity).cgColor,
                NSColor(look.gradientEnd).withAlphaComponent(look.opacity).cgColor,
            ]
            return layer
        }
    }

    /// A soft shadow around the pieces and none under them: seen through a translucent tint, it would darken it.
    private static func shadow(around outline: CGPath, bounds: CGRect) -> CALayer {
        let shade = CALayer()
        shade.frame = bounds
        shade.shadowPath = outline
        shade.shadowColor = NSColor.black.cgColor
        shade.shadowOpacity = 0.3
        shade.shadowRadius = 4
        shade.shadowOffset = CGSize(width: 0, height: -2)
        let outside = CGMutablePath()
        outside.addRect(bounds)
        outside.addPath(outline)
        let cut = CAShapeLayer()
        cut.frame = bounds
        cut.path = outside
        cut.fillRule = .evenOdd
        shade.mask = cut
        return shade
    }
}

extension TintGeometry.Pieces {
    /// The outline of the pieces, with the continuous corners of macOS's own capsules. `inset` brings it inside the
    /// edge, for a stroke that stays within the pieces.
    func outline(inset: CGFloat = 0) -> Path {
        var path = Path()
        for rect in rects {
            let inner = rect.insetBy(dx: inset, dy: inset)
            let corner = max(0, min(radius - inset, inner.width / 2, inner.height / 2))
            path.addPath(RoundedRectangle(cornerRadius: corner, style: .continuous).path(in: inner))
        }
        return path
    }
}
