import AppKit
import IsletCore

/// Draws the two wings of the compact island with plain Core Animation layers.
///
/// Everything that moves here, the equalizer above all, runs as a repeating animation inside the render server: once
/// it is set up, the app itself does no work per frame and stays at zero CPU while music plays.
@MainActor
final class CompactRenderer {
    let layer = CALayer()
    private var leading = WingSlot()
    private var trailing = WingSlot()
    private var images: [String: CGImage] = [:]
    private var scale: CGFloat = 2

    init() {
        layer.addSublayer(leading.container)
        layer.addSublayer(trailing.container)
    }

    func setScale(_ scale: CGFloat) {
        self.scale = scale
    }

    /// The images registered so far, for a second island that shows the same wings.
    var registeredImages: [String: CGImage] { images }

    /// Makes an image available to `.image(key:)` items.
    func register(_ image: CGImage?, for key: String) {
        images[key] = image
        for slot in [leading, trailing] where slot.item == .image(key: key) {
            slot.content.contents = image
        }
    }

    /// Width one wing needs to show `presentation` comfortably, both wings sharing the wider of the two.
    func wingWidth(for presentation: CompactPresentation?, notchHeight: CGFloat) -> CGFloat {
        guard let presentation else { return 0 }
        let widths = [presentation.leading, presentation.trailing].compactMap { $0 }.map {
            itemWidth($0, notchHeight: notchHeight) + WingSlot.padding * 2
        }
        return widths.max() ?? 0
    }

    private func itemWidth(_ item: CompactItem, notchHeight: CGFloat) -> CGFloat {
        let side = WingSlot.side(for: notchHeight)
        switch item {
        case .text(let string, _):
            return min(ceil(TextMetrics.width(of: string)), IslandLayout.maximumWing - WingSlot.padding * 2)
        case .level:
            return side * 2.4
        case .battery:
            return side * 1.5
        default:
            return side
        }
    }

    /// Shows `presentation`, positioning each item in the middle of its wing.
    func show(_ presentation: CompactPresentation?, layout: IslandLayout, wings: Wings, canvasHeight: CGFloat) {
        let height = layout.notch.height
        for (slot, item, isLeading) in [(leading, presentation?.leading, true), (trailing, presentation?.trailing, false)] {
            let center = layout.wingCenter(leading: isLeading, wings: wings)
            // Canvas coordinates are top-left; the layer tree is bottom-left.
            let position = CGPoint(x: center.x, y: canvasHeight - center.y)
            // A wing narrowed to spare the menu bar narrows its item too; text then truncates.
            let wing = isLeading ? wings.leading : wings.trailing
            let width = min(item.map { itemWidth($0, notchHeight: height) } ?? 0, max(0, wing - WingSlot.padding * 2))
            slot.update(item, size: CGSize(width: width, height: WingSlot.side(for: height)), position: position, images: images, scale: scale)
        }
    }

    func setVisible(_ visible: Bool, animated: Bool) {
        let opacity: Float = visible ? 1 : 0
        if animated {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
            fade.toValue = opacity
            fade.duration = visible ? 0.3 : 0.12
            fade.beginTime = CACurrentMediaTime() + (visible ? 0.1 : 0)
            fade.fillMode = .backwards
            layer.add(fade, forKey: "opacity")
        }
        layer.opacity = opacity
    }
}

/// One wing: a container that crossfades when the item changes, holding the layers of the current item.
@MainActor
private final class WingSlot {
    static let padding: CGFloat = 9
    static func side(for notchHeight: CGFloat) -> CGFloat { max(14, notchHeight - 12) }

    let container = CALayer()
    /// Image or symbol contents.
    let content = CALayer()
    private var parts: [CALayer] = []
    private(set) var item: CompactItem?

    init() {
        container.addSublayer(content)
        content.contentsGravity = .resizeAspect
        content.masksToBounds = true
    }

    func update(_ item: CompactItem?, size: CGSize, position: CGPoint, images: [String: CGImage], scale: CGFloat) {
        let kindChanged = !Self.sameKind(self.item, item)
        let moved = container.position != position
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if kindChanged, self.item != nil || item != nil {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.22
            container.add(fade, forKey: "swap")
        }
        if moved, self.item != nil, item != nil {
            let slide = CASpringAnimation(perceptualDuration: 0.4, bounce: 0.15)
            slide.keyPath = "position"
            slide.fromValue = container.presentation()?.position ?? container.position
            slide.toValue = position
            slide.duration = slide.settlingDuration
            container.add(slide, forKey: "position")
        }
        container.bounds = CGRect(origin: .zero, size: size)
        container.position = position
        content.frame = container.bounds
        content.contentsScale = scale

        if kindChanged { reset() }
        self.item = item
        guard let item else {
            content.contents = nil
            CATransaction.commit()
            return
        }
        switch item {
        case .symbol(let name, let tint):
            content.cornerRadius = 0
            content.contents = SymbolRenderer.image(name, tint: tint, pointSize: size.height * 0.82, scale: scale)
        case .image(let key):
            content.cornerRadius = size.height * 0.26
            content.contentsGravity = .resizeAspectFill
            content.contents = images[key]
        case .equalizer(let tint, let playing):
            content.contents = nil
            drawEqualizer(size: size, tint: tint, playing: playing, restart: kindChanged)
        case .text(let string, let tint):
            content.contents = nil
            drawText(string, size: size, tint: tint, scale: scale)
        case .ring(let progress, let tint):
            content.contents = nil
            drawRing(progress: progress, size: size, tint: tint)
        case .level(let value, let tint):
            content.contents = nil
            drawLevel(value, size: size, tint: tint)
        case .battery(let level, let charging):
            content.contents = nil
            drawBattery(level: level, charging: charging, size: size)
        case .spinner(let tint):
            content.contents = nil
            drawSpinner(size: size, tint: tint)
        case .countdown(let ends, let total, let tint):
            content.contents = nil
            drawCountdown(ends: ends, total: total, size: size, tint: tint)
        case .appIcon(let icon, let bouncing):
            content.contents = nil
            drawAppIcon(icon, bouncing: bouncing, size: size, scale: scale)
        }
        CATransaction.commit()
    }

    private static func sameKind(_ a: CompactItem?, _ b: CompactItem?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case (.symbol(let x, _), .symbol(let y, _)): x == y
        case (.image(let x), .image(let y)): x == y
        case (.equalizer, .equalizer), (.text, .text), (.ring, .ring), (.level, .level), (.battery, .battery), (.spinner, .spinner), (.countdown, .countdown): true
        case (.appIcon(let x, _), .appIcon(let y, _)): x == y
        default: false
        }
    }

    private func reset() {
        parts.forEach { $0.removeFromSuperlayer() }
        parts = []
        content.contentsGravity = .resizeAspect
    }

    private func part<T: CALayer>(_ index: Int, _ make: () -> T) -> T {
        if index < parts.count, let existing = parts[index] as? T { return existing }
        let layer = make()
        container.addSublayer(layer)
        parts.append(layer)
        return layer
    }

    // MARK: Items

    /// The app's own icon. App icons keep a margin around their tile, so it is drawn a little larger than a symbol to
    /// look the same size. While the app needs the user it bounces as Dock icons do, low enough to stay in the island.
    private func drawAppIcon(_ icon: AppIcon, bouncing: Bool, size: CGSize, scale: CGFloat) {
        let image = part(0) { CALayer() }
        let found = AppIcons.image(for: icon, side: size.height * 1.15, scale: scale)
        let side = found == nil ? size.height : size.height * 1.15
        image.contentsGravity = .resizeAspect
        image.contentsScale = scale
        image.contents = found ?? SymbolRenderer.image(icon.symbol, tint: icon.tint, pointSize: size.height * 0.82, scale: scale)
        image.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        image.position = CGPoint(x: size.width / 2, y: size.height / 2)
        let bounces = bouncing && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if bounces, image.animation(forKey: "bounce") == nil {
            let bounce = CAKeyframeAnimation(keyPath: "transform.translation.y")
            bounce.values = [0, size.height * 0.2, 0, 0]
            bounce.keyTimes = [0, 0.28, 0.56, 1]
            bounce.timingFunctions = [
                CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn), CAMediaTimingFunction(name: .linear),
            ]
            bounce.duration = 0.95
            bounce.repeatCount = .infinity
            image.add(bounce, forKey: "bounce")
        } else if !bounces {
            image.removeAnimation(forKey: "bounce")
        }
    }

    private func drawEqualizer(size: CGSize, tint: RGBA, playing: Bool, restart: Bool) {
        let count = 4
        let gap = size.width * 0.12
        let barWidth = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
        // Each bar breathes at its own pace, so together they never fall into step.
        let periods: [CFTimeInterval] = [0.46, 0.34, 0.52, 0.4]
        let peaks: [CGFloat] = [0.95, 0.7, 1, 0.8]
        for index in 0..<count {
            let bar = part(index) { CALayer() }
            bar.backgroundColor = tint.cgColor
            bar.cornerRadius = barWidth / 2
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: size.height)
            bar.position = CGPoint(x: barWidth / 2 + CGFloat(index) * (barWidth + gap), y: size.height / 2)
            let resting = barWidth / size.height
            if playing {
                if restart || bar.animation(forKey: "dance") == nil {
                    let dance = CABasicAnimation(keyPath: "transform.scale.y")
                    dance.fromValue = 0.22
                    dance.toValue = peaks[index]
                    dance.duration = periods[index]
                    dance.autoreverses = true
                    dance.repeatCount = .infinity
                    dance.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    dance.timeOffset = periods[index] * Double(index) * 0.37
                    bar.add(dance, forKey: "dance")
                }
                bar.transform = CATransform3DMakeScale(1, 0.22, 1)
            } else {
                // Settle to dots, from wherever the bar was.
                let current = (bar.presentation()?.value(forKeyPath: "transform.scale.y") as? CGFloat) ?? resting
                bar.removeAnimation(forKey: "dance")
                let settle = CASpringAnimation(perceptualDuration: 0.35, bounce: 0.2)
                settle.keyPath = "transform.scale.y"
                settle.fromValue = current
                settle.toValue = resting
                settle.duration = settle.settlingDuration
                bar.add(settle, forKey: "settle")
                bar.transform = CATransform3DMakeScale(1, resting, 1)
            }
        }
    }

    private func drawText(_ string: String, size: CGSize, tint: RGBA, scale: CGFloat) {
        let text = part(0) { CATextLayer() }
        text.string = NSAttributedString(string: string, attributes: [
            .font: TextMetrics.font,
            .foregroundColor: tint.nsColor,
        ])
        text.truncationMode = .end
        text.contentsScale = scale
        text.alignmentMode = .center
        let line = ceil(TextMetrics.font.ascender - TextMetrics.font.descender)
        text.frame = CGRect(x: 0, y: (size.height - line) / 2, width: size.width, height: line)
    }

    private func drawRing(progress: Double, size: CGSize, tint: RGBA) {
        let side = min(size.width, size.height)
        let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side).insetBy(dx: 1.5, dy: 1.5)
        let track = part(0) { CAShapeLayer() }
        let fill = part(1) { CAShapeLayer() }
        for (shape, color) in [(track, tint.withAlpha(0.25)), (fill, tint)] {
            shape.path = CGPath(ellipseIn: rect, transform: nil)
            shape.fillColor = nil
            shape.strokeColor = color.cgColor
            shape.lineWidth = 3
            shape.lineCap = .round
            shape.frame = CGRect(origin: .zero, size: size)
        }
        // Start at twelve o'clock and run clockwise.
        fill.transform = CATransform3DConcat(CATransform3DMakeScale(-1, 1, 1), CATransform3DMakeRotation(-.pi / 2, 0, 0, 1))
        let clamped = min(max(progress, 0), 1)
        let grow = CABasicAnimation(keyPath: "strokeEnd")
        grow.fromValue = fill.presentation()?.strokeEnd ?? fill.strokeEnd
        grow.toValue = clamped
        grow.duration = 0.3
        fill.add(grow, forKey: "strokeEnd")
        fill.strokeEnd = clamped
    }

    private func drawLevel(_ value: Double, size: CGSize, tint: RGBA) {
        let height: CGFloat = 5
        let track = part(0) { CALayer() }
        let fill = part(1) { CALayer() }
        let rect = CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
        track.frame = rect
        track.cornerRadius = height / 2
        track.backgroundColor = tint.withAlpha(0.22).cgColor
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.cornerRadius = height / 2
        fill.backgroundColor = tint.cgColor
        fill.position = CGPoint(x: rect.minX, y: rect.midY)
        let width = rect.width * CGFloat(min(max(value, 0), 1))
        let target = CGRect(x: 0, y: 0, width: width, height: height)
        let slide = CASpringAnimation(perceptualDuration: 0.25, bounce: 0)
        slide.keyPath = "bounds"
        slide.fromValue = fill.presentation()?.bounds ?? fill.bounds
        slide.toValue = target
        slide.duration = slide.settlingDuration
        fill.add(slide, forKey: "bounds")
        fill.bounds = target
    }

    /// The ring empties over the time left, as one long animation: the app does nothing until the timer rings.
    private func drawCountdown(ends: Date, total: TimeInterval, size: CGSize, tint: RGBA) {
        let side = min(size.width, size.height)
        let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side).insetBy(dx: 1.5, dy: 1.5)
        let track = part(0) { CAShapeLayer() }
        let fill = part(1) { CAShapeLayer() }
        for (shape, color) in [(track, tint.withAlpha(0.22)), (fill, tint)] {
            shape.path = CGPath(ellipseIn: rect, transform: nil)
            shape.fillColor = nil
            shape.strokeColor = color.cgColor
            shape.lineWidth = 3
            shape.lineCap = .round
            shape.frame = CGRect(origin: .zero, size: size)
        }
        fill.transform = CATransform3DConcat(CATransform3DMakeScale(-1, 1, 1), CATransform3DMakeRotation(-.pi / 2, 0, 0, 1))
        let left = max(ends.timeIntervalSinceNow, 0)
        let now = left / max(total, 1)
        fill.removeAnimation(forKey: "countdown")
        fill.strokeEnd = 0
        guard left > 0 else { return }
        let drain = CABasicAnimation(keyPath: "strokeEnd")
        drain.fromValue = now
        drain.toValue = 0
        drain.duration = left
        drain.timingFunction = CAMediaTimingFunction(name: .linear)
        fill.add(drain, forKey: "countdown")
    }

    private func drawSpinner(size: CGSize, tint: RGBA) {
        let side = min(size.width, size.height) * 0.86
        let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
        let track = part(0) { CAShapeLayer() }
        let arc = part(1) { CAShapeLayer() }
        for (shape, color, end) in [(track, tint.withAlpha(0.2), 1.0), (arc, tint, 0.28)] {
            shape.frame = rect
            shape.path = CGPath(ellipseIn: CGRect(origin: .zero, size: rect.size).insetBy(dx: 1.5, dy: 1.5), transform: nil)
            shape.fillColor = nil
            shape.strokeColor = color.cgColor
            shape.lineWidth = 2.6
            shape.lineCap = .round
            shape.strokeEnd = end
        }
        // Turns inside the render server: no work for the app while it spins.
        if arc.animation(forKey: "spin") == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -2 * Double.pi
            spin.duration = 0.9
            spin.repeatCount = .infinity
            arc.add(spin, forKey: "spin")
        }
    }

    private func drawBattery(level: Double, charging: Bool, size: CGSize) {
        let bodyHeight = size.height * 0.62
        let body = CGRect(x: 0, y: (size.height - bodyHeight) / 2, width: size.width - 3, height: bodyHeight)
        let shell = part(0) { CAShapeLayer() }
        let cap = part(1) { CALayer() }
        let fill = part(2) { CALayer() }
        let bolt = part(3) { CALayer() }
        shell.path = CGPath(roundedRect: body.insetBy(dx: 0.75, dy: 0.75), cornerWidth: 4, cornerHeight: 4, transform: nil)
        shell.fillColor = nil
        shell.strokeColor = NSColor.white.withAlphaComponent(0.45).cgColor
        shell.lineWidth = 1.5
        shell.frame = CGRect(origin: .zero, size: size)
        cap.frame = CGRect(x: body.maxX + 0.5, y: body.midY - 2.5, width: 2, height: 5)
        cap.cornerRadius = 1
        cap.backgroundColor = NSColor.white.withAlphaComponent(0.45).cgColor
        let clamped = min(max(level, 0), 1)
        let tint: RGBA = charging || clamped > 0.2 ? .green : .red
        let inner = body.insetBy(dx: 2.5, dy: 2.5)
        fill.frame = CGRect(x: inner.minX, y: inner.minY, width: max(2, inner.width * clamped), height: inner.height)
        fill.cornerRadius = 2
        fill.backgroundColor = tint.cgColor
        bolt.contents = charging ? SymbolRenderer.image("bolt.fill", tint: .white, pointSize: bodyHeight * 0.8, scale: content.contentsScale) : nil
        bolt.contentsGravity = .resizeAspect
        bolt.frame = body
        bolt.contentsScale = content.contentsScale
    }
}

@MainActor
enum TextMetrics {
    static let font = NSFont.systemFont(ofSize: 13, weight: .semibold)

    static func width(of string: String) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }
}

enum SymbolRenderer {
    @MainActor private static var cache: [String: CGImage] = [:]

    /// Renders an SF Symbol to a bitmap once per name, tint and size.
    @MainActor
    static func image(_ name: String, tint: RGBA, pointSize: CGFloat, scale: CGFloat) -> CGImage? {
        let key = "\(name)|\(tint)|\(pointSize)|\(scale)"
        if let cached = cache[key] { return cached }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tint.nsColor]))
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else {
            return nil
        }
        var rect = NSRect(origin: .zero, size: symbol.size)
        let pixels = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        let bitmap = NSImage(size: pixels, flipped: false) { _ in
            symbol.draw(in: NSRect(origin: .zero, size: pixels))
            return true
        }
        rect.size = pixels
        let image = bitmap.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        if cache.count > 64 { cache.removeAll() }
        cache[key] = image
        return image
    }
}

extension RGBA {
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
    var cgColor: CGColor { nsColor.cgColor }
    func withAlpha(_ value: Double) -> RGBA { RGBA(red: red, green: green, blue: blue, alpha: value) }
}
