import AppKit
import ColCore

/// The intro Col plays as it opens (IntroScore): light runs around the notch, the island swells out of it on the first
/// bell of a rising chime, with Col in its left wing and bars that ring with the bells in its right one, each bell sends
/// a wave out over the desktop, then the island tucks back in.
///
/// Everything is laid out once and handed to the render server with its start times, the chime started at the same
/// moment, so the picture keeps time with the sound however busy the app is as it starts. The window exists for the
/// intro alone: once it has played, it goes with its layers and its sound, and Col keeps nothing of it.
@MainActor
final class StartupIntro {
    struct Setup {
        var screen: NSScreen
        var layout: IslandLayout
        /// The swollen island's wings, placed by the island's own rules: beside the camera, or in the strip beneath
        /// it when the menu bar leaves no room there.
        var wings: Wings
        /// The island shows while idle (a pill, a drawn notch). Hidden at rest, it fades in with the light.
        var restVisible: Bool
        var tint: NSColor
        var icon: CGImage?
        var playsSound: Bool
        var hiddenFromCapture: Bool
    }

    /// The chime, as Col bundles it (scripts/make-intro-sound.sh).
    static var soundURL: URL? { Bundle.module.url(forResource: "Intro", withExtension: "m4a") }
    /// How loud the chime plays, as a share of the Mac's volume.
    static let volume: Float = 0.55

    private let setup: Setup
    private let panel = IntroPanel()
    private let canvas: CGSize
    private let root = CALayer()
    private var sound: NSSound?
    private var completion: (() -> Void)?
    private var finished = false
    private var base: CFTimeInterval = 0

    init(_ setup: Setup) {
        self.setup = setup
        let swollen = setup.layout.shape(for: .collapsed, wings: setup.wings)
        let reach = IntroScore.waveReach
        let margin: CGFloat = 44
        canvas = CGSize(
            width: ceil(swollen.outerWidth + abs(swollen.offset) * 2 + reach.width * 2 + margin * 2),
            height: ceil(swollen.gap + swollen.height + reach.height + margin)
        )
        let screen = setup.screen.frame
        panel.setFrame(NSRect(x: (screen.minX + setup.layout.notch.centerX - canvas.width / 2).rounded(),
                              y: screen.maxY - canvas.height, width: canvas.width, height: canvas.height), display: false)
        panel.sharingType = setup.hiddenFromCapture ? .none : .readOnly
        let view = NSView(frame: NSRect(origin: .zero, size: canvas))
        view.wantsLayer = true
        view.setAccessibilityElement(false)
        root.frame = view.bounds
        root.contentsScale = setup.screen.backingScaleFactor
        view.layer?.addSublayer(root)
        panel.contentView = view
    }

    /// Plays the intro; `completion` runs once it has played, or once it was cut short.
    func play(completion: @escaping () -> Void) {
        self.completion = completion
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.orderFrontRegardless()
        if setup.playsSound, let url = Self.soundURL, let sound = NSSound(contentsOf: url, byReference: true) {
            sound.volume = Self.volume
            self.sound = sound
        }
        // The window takes a frame to reach the screen and the sound a few milliseconds to start: the score begins
        // just after, for both.
        base = CACurrentMediaTime() + 0.05
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        compose(still: still)
        CATransaction.commit()
        sound?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 + IntroScore.end + 0.05) { [weak self] in
            MainActor.assumeIsolated { self?.finish() }
        }
    }

    /// Ends the intro now, in a short fade: the user reached for the island, or something needs it.
    func cut() {
        guard !finished else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = root.presentation()?.opacity ?? 1
        fade.toValue = 0
        fade.duration = 0.15
        root.opacity = 0
        root.add(fade, forKey: "cut")
        sound?.stop()
        // The island takes over at once; the window only fades, and is kept until it has gone.
        completion?()
        completion = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            MainActor.assumeIsolated { self.finish() }
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        panel.orderOut(nil)
        root.removeFromSuperlayer()
        panel.contentView = nil
        // The last bell rings on a little after the picture has settled.
        if let sound, sound.isPlaying {
            DispatchQueue.main.asyncAfter(deadline: .now() + IntroScore.soundDuration - IntroScore.end) { _ = sound }
        }
        sound = nil
        completion?()
        completion = nil
    }

    // MARK: The picture

    private var flip: CGAffineTransform { CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: canvas.height) }

    /// A path drawn in the top-left space of the score, in the layers' bottom-left one.
    private func flipped(_ path: CGPath) -> CGPath {
        var transform = flip
        return path.copy(using: &transform) ?? path
    }

    private func flipped(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: canvas.height - point.y) }

    private func at(_ time: Double) -> CFTimeInterval { base + time }

    private func compose(still: Bool) {
        let layout = setup.layout
        let rest = layout.shape(for: .collapsed)
        let swollen = setup.wings.isEmpty ? rest : layout.shape(for: .collapsed, wings: setup.wings)
        let floating = rest.isFloating
        let centerX = canvas.width / 2
        func outline(_ shape: IslandShape) -> CGPath {
            flipped(IntroGeometry.path(shape, centerX: centerX + shape.offset, floating: floating))
        }
        let tint = setup.tint.usingColorSpace(.sRGB) ?? setup.tint
        // The waves and the glow show below the menu bar only, so its menus and icons stay clear.
        let field = CALayer()
        field.frame = root.bounds
        field.mask = menuBarFade()
        root.addSublayer(field)
        field.addSublayer(glow(outline(swollen), tint: tint))
        if !still {
            for (index, bell) in IntroScore.bells.enumerated() {
                // The first wave leaves with the swell, from the island as it was; the others from the swollen island.
                let from = index == 0 ? rest : swollen
                field.addSublayer(wave(from: outline(from), to: outline(IntroGeometry.wave(from: swollen, progress: 1)),
                                       at: bell, strength: [1, 0.8, 0.72, 0.95][index], tint: tint))
            }
        }
        // The light runs just under the island's edge: as the island swells, it covers it.
        if !still {
            let halves = IntroGeometry.traceHalves(rest, centerX: centerX + rest.offset)
            root.addSublayer(trace(flipped(halves.left), tint: tint))
            root.addSublayer(trace(flipped(halves.right), tint: tint))
        }
        root.addSublayer(island(rest: outline(rest), swollen: outline(swollen), still: still))
        if !still {
            root.addSublayer(flash(at: flipped(CGPoint(x: centerX + rest.offset, y: rest.gap + rest.height)), tint: tint))
        }
        if !setup.wings.isEmpty { root.addSublayer(wingContents(tint: tint, still: still)) }
    }

    /// The black island, swelling out of the notch with the first bell and tucking back in as the chord lets go.
    private func island(rest: CGPath, swollen: CGPath, still: Bool) -> CAShapeLayer {
        let island = CAShapeLayer()
        island.fillColor = NSColor.black.cgColor
        island.path = still ? swollen : rest
        let hardware = setup.layout.notch.isHardware && setup.layout.style == nil
        if still {
            // Without motion, the swollen island fades in and out.
            island.opacity = 0
            island.add(keyframes("opacity", [0, 1, 1, 0], at: [IntroScore.swell, IntroScore.swell + 0.25, IntroScore.tuck, IntroScore.tuck + 0.3]), forKey: "opacity")
            return island
        }
        let swell = CASpringAnimation(perceptualDuration: 0.5, bounce: 0.28)
        swell.keyPath = "path"
        swell.fromValue = rest
        swell.toValue = swollen
        swell.beginTime = at(IntroScore.swell)
        swell.duration = swell.settlingDuration
        swell.fillMode = .both
        swell.isRemovedOnCompletion = false
        island.add(swell, forKey: "swell")
        let tuck = CASpringAnimation(perceptualDuration: 0.42, bounce: 0)
        tuck.keyPath = "path"
        tuck.fromValue = swollen
        tuck.toValue = rest
        tuck.beginTime = at(IntroScore.tuck)
        tuck.duration = tuck.settlingDuration
        tuck.fillMode = .forwards
        tuck.isRemovedOnCompletion = false
        island.add(tuck, forKey: "tuck")
        // Under a notch the island at rest is the notch's own black; elsewhere, an island hidden at rest fades in with
        // the light, and away once it has tucked back in.
        if !hardware, !setup.restVisible {
            island.opacity = 0
            island.add(keyframes("opacity", [0, 1, 1, 0], at: [IntroScore.traceEnd - 0.14, IntroScore.swell + 0.04, IntroScore.tuck + 0.25, IntroScore.end - 0.02]),
                       forKey: "opacity")
        }
        return island
    }

    /// A line of light running along one half of the island's outline, from its top to the middle of its lower edge.
    private func trace(_ path: CGPath, tint: NSColor) -> CAShapeLayer {
        let line = CAShapeLayer()
        line.path = path
        line.fillColor = nil
        line.strokeColor = NSColor.white.withAlphaComponent(0.95).cgColor
        line.lineWidth = 1.6
        line.lineCap = .round
        line.lineJoin = .round
        line.shadowColor = tint.cgColor
        line.shadowRadius = 4
        line.shadowOpacity = 0.9
        line.shadowOffset = .zero
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.beginTime = at(IntroScore.traceStart)
        draw.duration = IntroScore.traceEnd - IntroScore.traceStart
        // Gathering speed toward the meeting point.
        draw.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.9, 0.6)
        draw.fillMode = .backwards
        line.add(draw, forKey: "draw")
        line.opacity = 0
        line.add(keyframes("opacity", [1, 1, 0], at: [IntroScore.traceStart, IntroScore.traceEnd, IntroScore.traceEnd + 0.3]), forKey: "opacity")
        return line
    }

    /// The spark where the two lines of light meet.
    private func flash(at point: CGPoint, tint: NSColor) -> CALayer {
        let spark = CALayer()
        spark.bounds = CGRect(x: 0, y: 0, width: 6, height: 6)
        spark.cornerRadius = 3
        spark.position = point
        spark.backgroundColor = NSColor.white.cgColor
        spark.shadowColor = tint.cgColor
        spark.shadowRadius = 12
        spark.shadowOpacity = 1
        spark.shadowOffset = .zero
        spark.opacity = 0
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 0]
        fade.keyTimes = [0, 0.15, 1]
        let grow = CAKeyframeAnimation(keyPath: "transform.scale")
        grow.values = [0.4, 1.2, 1.7]
        grow.keyTimes = [0, 0.15, 1]
        let group = CAAnimationGroup()
        group.animations = [fade, grow]
        group.beginTime = at(IntroScore.traceEnd - 0.02)
        group.duration = 0.5
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.fillMode = .backwards
        spark.add(group, forKey: "flash")
        return spark
    }

    /// A soft light under the island that swells with the bells.
    private func glow(_ path: CGPath, tint: NSColor) -> CALayer {
        let glow = CALayer()
        glow.frame = root.bounds
        glow.shadowPath = path
        glow.shadowColor = tint.cgColor
        glow.shadowRadius = 30
        glow.shadowOffset = .zero
        glow.shadowOpacity = 0
        let bells = IntroScore.bells
        glow.add(keyframes("shadowOpacity", [0, 1, 0.65, 0.9, 0.7, 1, 0.55, 0],
                           at: [IntroScore.swell + 0.05, bells[0] + 0.15, bells[1] - 0.02, bells[1] + 0.1, bells[2] + 0.02, bells[3] + 0.12, 1.45, IntroScore.tuck + 0.1]),
                 forKey: "glow")
        return glow
    }

    /// One wave: the island's outline leaving it with a bell, growing out over the desktop as it fades.
    private func wave(from start: CGPath, to end: CGPath, at time: Double, strength: Float, tint: NSColor) -> CAShapeLayer {
        let wave = CAShapeLayer()
        wave.fillColor = nil
        // Lighter than the accent, with a halo of it, so a wave reads on any desktop.
        wave.strokeColor = tint.blended(withFraction: 0.5, of: .white)?.cgColor ?? tint.cgColor
        wave.shadowColor = tint.cgColor
        wave.shadowRadius = 4
        wave.shadowOpacity = 0.8
        wave.shadowOffset = .zero
        wave.lineWidth = 1
        wave.path = end
        wave.opacity = 0
        let grow = CABasicAnimation(keyPath: "path")
        grow.fromValue = start
        grow.toValue = end
        let thin = CABasicAnimation(keyPath: "lineWidth")
        thin.fromValue = 2.6
        thin.toValue = 1
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 0.95 * strength, 0]
        fade.keyTimes = [0, 0.1, 1]
        let group = CAAnimationGroup()
        group.animations = [grow, thin, fade]
        group.beginTime = at(time)
        group.duration = IntroScore.waveDuration
        // Leaving fast, slowing as it spreads, like a ripple.
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.15, 0.6, 0.3, 1)
        group.fillMode = .backwards
        wave.add(group, forKey: "wave")
        return wave
    }

    /// Col in the left wing, and in the right one four bars that ring with the bells.
    private func wingContents(tint: NSColor, still: Bool) -> CALayer {
        let layout = setup.layout
        let wings = setup.wings
        let beneath = wings.beneath && layout.canHangBeneath
        let side = beneath ? IslandLayout.beneathItem : max(14, layout.notch.height - 14)
        let shift = canvas.width / 2 - layout.canvasSize.width / 2
        func center(leading: Bool) -> CGPoint {
            let point = layout.wingCenter(leading: leading, wings: wings)
            return flipped(CGPoint(x: point.x + shift, y: point.y))
        }
        let contents = CALayer()
        contents.frame = root.bounds
        contents.opacity = 0
        contents.add(keyframes("opacity", [0, 1, 1, 0], at: [IntroScore.swell + 0.08, IntroScore.swell + 0.3, IntroScore.tuck - 0.2, IntroScore.tuck - 0.02]),
                     forKey: "opacity")

        // A single wing carries one item, as for an activity: the bars, the intro's value.
        let oneSided = wings.isOneSided
        let barsLeading = oneSided && wings.leading > 0
        if let image = setup.icon, !oneSided {
            let icon = CALayer()
            let size = side * 1.15
            icon.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            icon.position = center(leading: true)
            icon.contents = image
            icon.contentsGravity = .resizeAspect
            icon.contentsScale = setup.screen.backingScaleFactor
            if !still {
                let pop = CASpringAnimation(perceptualDuration: 0.45, bounce: 0.35)
                pop.keyPath = "transform.scale"
                pop.fromValue = 0.55
                pop.toValue = 1
                pop.beginTime = at(IntroScore.swell + 0.08)
                pop.duration = pop.settlingDuration
                pop.fillMode = .backwards
                icon.add(pop, forKey: "pop")
            }
            contents.addSublayer(icon)
        }

        // The same bars as the equalizer of a song playing, in the accent.
        let count = 4
        let gap = side * 0.12
        let barWidth = (side - gap * CGFloat(count - 1)) / CGFloat(count)
        let middle = center(leading: barsLeading)
        for index in 0..<count {
            let bar = CALayer()
            bar.backgroundColor = tint.cgColor
            bar.cornerRadius = barWidth / 2
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: side)
            bar.position = CGPoint(x: middle.x - side / 2 + barWidth / 2 + CGFloat(index) * (barWidth + gap), y: middle.y)
            let resting = max(IntroScore.barRest, Double(barWidth / side))
            bar.transform = CATransform3DMakeScale(1, CGFloat(still ? 0.5 : resting), 1)
            if !still {
                let values = IntroScore.barKeyframes(index).map { max($0, resting) }
                let ring = CAKeyframeAnimation(keyPath: "transform.scale.y")
                ring.values = values
                ring.keyTimes = values.indices.map { NSNumber(value: Double($0) / Double(max(values.count - 1, 1))) }
                ring.beginTime = at(IntroScore.swell)
                ring.duration = IntroScore.tuck - IntroScore.swell
                ring.calculationMode = .linear
                ring.fillMode = .backwards
                bar.add(ring, forKey: "ring")
            }
            contents.addSublayer(bar)
        }
        return contents
    }

    /// A mask that hides the menu bar's row and fades in just below it, then out toward the window's lower edge.
    private func menuBarFade() -> CAGradientLayer {
        let mask = CAGradientLayer()
        mask.frame = root.bounds
        let height = canvas.height
        let bar = setup.layout.notch.height
        mask.colors = [NSColor.clear, .clear, .white, .white, .clear].map(\.cgColor)
        mask.locations = [0, bar / height, min(bar + 18, height) / height, 0.82, 1].map { NSNumber(value: Double($0)) }
        // From the top of the window down.
        mask.startPoint = CGPoint(x: 0.5, y: 1)
        mask.endPoint = CGPoint(x: 0.5, y: 0)
        return mask
    }

    /// Keyframes of `keyPath` at the given times of the score, played once from the first of them.
    private func keyframes(_ keyPath: String, _ values: [Double], at times: [Double]) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        let start = times.first ?? 0
        let span = max((times.last ?? start) - start, 0.001)
        animation.values = values
        animation.keyTimes = times.map { NSNumber(value: ($0 - start) / span) }
        animation.beginTime = at(start)
        animation.duration = span
        animation.fillMode = .backwards
        return animation
    }
}

/// A borderless window over the notch that never takes a click nor the focus, above the menu bar like the island.
private final class IntroPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        setAccessibilityElement(false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// AppKit pushes windows below the menu bar; the intro lives in it, as the island does.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
