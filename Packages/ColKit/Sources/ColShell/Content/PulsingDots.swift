import AppKit
import SwiftUI

/// Three dots that pulse in turn: a model writing, a model thinking, music playing without words. The render server
/// plays them, as it plays the equalizer: drawn by SwiftUI, the same motion redrew the island many times a second and
/// held 100 MB more for as long as it ran. Still with Reduce Motion, and while `active` is off.
struct PulsingDots: NSViewRepresentable {
    enum Motion {
        /// Each dot fades up in turn, as in Messages while someone types.
        case fade
        /// Each dot swells in turn.
        case swell
    }

    var color: NSColor
    var dot: CGFloat
    var spacing: CGFloat
    var motion: Motion = .fade
    var active = true

    func makeNSView(context: Context) -> DotsView { DotsView() }

    func updateNSView(_ view: DotsView, context: Context) {
        view.show(color: color, dot: dot, spacing: spacing, motion: motion, active: active)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DotsView, context: Context) -> CGSize? {
        CGSize(width: dot * 3 + spacing * 2, height: dot * 1.3)
    }
}

final class DotsView: NSView {
    private let dots = (0..<3).map { _ in CALayer() }
    private var dot: CGFloat = 4
    private var spacing: CGFloat = 3
    private var playing: PulsingDots.Motion?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        dots.forEach { layer?.addSublayer($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func show(color: NSColor, dot: CGFloat, spacing: CGFloat, motion: PulsingDots.Motion, active: Bool) {
        self.dot = dot
        self.spacing = spacing
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in dots {
            layer.backgroundColor = color.cgColor
            layer.cornerRadius = dot / 2
        }
        CATransaction.commit()
        needsLayout = true
        let moves = active && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard moves else {
            if playing != nil { dots.forEach { $0.removeAllAnimations() } }
            playing = nil
            dots.forEach { $0.opacity = motion == .fade ? 0.55 : 0.35 }
            return
        }
        guard playing != motion else { return }
        dots.forEach { $0.removeAllAnimations() }
        playing = motion
        let now = CACurrentMediaTime()
        for (index, layer) in dots.enumerated() {
            let pulse = CABasicAnimation(keyPath: motion == .fade ? "opacity" : "transform.scale")
            pulse.fromValue = motion == .fade ? 0.3 : 0.8
            pulse.toValue = motion == .fade ? 1 : 1.25
            pulse.duration = motion == .fade ? 0.45 : 0.7
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulse.beginTime = now + Double(index) * (motion == .fade ? 0.15 : 0.18)
            pulse.fillMode = .backwards
            layer.opacity = motion == .fade ? 1 : 0.9
            layer.add(pulse, forKey: "pulse")
        }
    }

    override func layout() {
        super.layout()
        let width = dot * 3 + spacing * 2
        let x = (bounds.width - width) / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, layer) in dots.enumerated() {
            layer.bounds = CGRect(x: 0, y: 0, width: dot, height: dot)
            layer.position = CGPoint(x: x + dot / 2 + CGFloat(index) * (dot + spacing), y: bounds.midY)
        }
        CATransaction.commit()
    }
}
