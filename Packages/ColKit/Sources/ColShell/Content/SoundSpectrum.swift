import AppKit
import ColCore
import SwiftUI

/// The spectrum of the sound in the player, when the bars follow the sound: a few slim bars from the bass up, in the
/// cover's colour. Drawn with Core Animation and fed the levels directly, so SwiftUI redraws nothing as they move;
/// it listens only while it is on screen, and fades away when the sound cannot be read.
struct SoundSpectrum: NSViewRepresentable {
    var bars = 12
    var color: NSColor

    func makeNSView(context: Context) -> SpectrumView { SpectrumView(bars: bars) }

    func updateNSView(_ view: SpectrumView, context: Context) {
        view.color = color
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SpectrumView, context: Context) -> CGSize? {
        CGSize(width: CGFloat(bars) * 3 + CGFloat(bars - 1) * 2, height: 16)
    }
}

final class SpectrumView: NSView {
    private let bars: [CALayer]
    /// Holds the bars; a layer of its own, so its fades animate (a view's own layer does not).
    private let container = CALayer()
    var color: NSColor = .white {
        didSet {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bars.forEach { $0.backgroundColor = color.cgColor }
            CATransaction.commit()
        }
    }

    init(bars count: Int) {
        bars = (0..<count).map { _ in CALayer() }
        super.init(frame: .zero)
        wantsLayer = true
        container.opacity = 0
        layer?.addSublayer(container)
        for bar in bars {
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.cornerRadius = 1.5
            bar.transform = CATransform3DMakeScale(1, 0.15, 1)
            container.addSublayer(bar)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let width: CGFloat = 3, gap: CGFloat = 2
        let total = CGFloat(bars.count) * width + CGFloat(bars.count - 1) * gap
        let start = (bounds.width - total) / 2
        container.frame = bounds
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            bar.position = CGPoint(x: start + width / 2 + CGFloat(index) * (width + gap), y: 0)
        }
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            SoundLevels.shared.subscribe(self) { [weak self] levels in self?.show(levels) }
        } else {
            SoundLevels.shared.unsubscribe(self)
        }
    }

    func show(_ levels: [Float]?) {
        guard let levels else {
            fade(to: 0)
            return
        }
        fade(to: 1)
        let heights = SpectrumBands.regroup(levels, into: bars.count)
        CATransaction.begin()
        CATransaction.setAnimationDuration(1.0 / 24)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        for (bar, height) in zip(bars, heights) {
            bar.transform = CATransform3DMakeScale(1, 0.15 + 0.85 * CGFloat(min(max(height, 0), 1)), 1)
        }
        CATransaction.commit()
    }

    private func fade(to opacity: Float) {
        guard container.opacity != opacity else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        container.opacity = opacity
        CATransaction.commit()
    }
}
