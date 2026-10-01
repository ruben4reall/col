import AppKit
import IsletCore

/// Stage light, as on the classic notch prompter: a soft light rising from the middle of the prompter's lower edge,
/// inside its outline. It is an ellipse centred on that edge that just reaches the top corners, strongest at its
/// centre and gone at four fifths of its radius. The presentation morphs the outline with the prompter; the
/// controller sets how bright it is.
final class GlowView: NSView {
    private let light = CAGradientLayer()
    private let clip = CAShapeLayer()
    /// Opacity of the light at the middle of the lower edge, at an intensity of 1.
    static let strength: CGFloat = 0.5
    /// A loud voice may push the intensity above 1, up to this.
    static let ceiling: CGFloat = 1.3

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.opacity = 0
        light.type = .radial
        light.locations = [0, 0.8]
        clip.fillColor = NSColor.black.cgColor
        light.mask = clip
        layer?.addSublayer(light)
        setColors(.violet)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Aims the light at a body, in this view's coordinates: centred on its lower edge.
    func configure(body: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        light.frame = bounds
        clip.frame = bounds
        let center = CGPoint(x: body.midX / bounds.width, y: body.minY / bounds.height)
        // Farthest corner: the ellipse through the top corners has the body's half width and height times √2.
        light.startPoint = center
        light.endPoint = CGPoint(x: center.x + body.width / 2 * 2.squareRoot() / bounds.width,
                                 y: center.y + body.height * 2.squareRoot() / bounds.height)
        CATransaction.commit()
    }

    /// The colour of the light, from Settings.
    func setColors(_ light: StageLight) {
        let lamp = StageTheme.lamp(light)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.light.colors = [lamp.withAlphaComponent(Self.strength * Self.ceiling).cgColor, lamp.withAlphaComponent(0).cgColor]
        CATransaction.commit()
        isOff = light == .off
        if isOff { setIntensity(0, duration: 0) }
    }
    private var isOff = false

    /// The outline the light is seen through; the presentation morphs it with the prompter.
    var outline: CAShapeLayer { clip }

    /// How bright the light is: 0 is off, 1 the resting light, up to `ceiling` with a loud voice. Eased.
    func setIntensity(_ value: CGFloat, duration: CFTimeInterval = 0.25) {
        guard let layer else { return }
        let target = isOff ? 0 : Float(max(0, min(Self.ceiling, value)) / Self.ceiling)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
        fade.toValue = target
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.opacity = target
        layer.add(fade, forKey: "opacity")
    }
}
