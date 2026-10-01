import AppKit
import IsletCore
import SwiftUI

/// The prompter growing out of the notch: it drops from the top of the screen around the camera housing with a
/// spring, the time on the camera's left and the voice on its right, the text right under it. Stage light rises
/// inside it from its lower edge, and a halo of the same colour lies beneath it.
@MainActor
final class NotchPresentation: PrompterPresentation {
    let text = ScriptTextView()
    private let state: PrompterState
    private let panel = PrompterPanel(movable: false)
    private let canvas = NotchCanvas()
    private let backdrop = ShapeView()
    private let glow = GlowView()
    private let content = NSView()
    private let mask = CAShapeLayer()
    private var overlay: PassthroughHostingView<PrompterOverlay>?
    private var wings: [NSView] = []
    private var layout: PrompterLayout?
    private var isOpen = false
    private var haloOpacity: Float = 0.25

    init(state: PrompterState) {
        self.state = state
        let root = NSView()
        root.wantsLayer = true
        panel.contentView = root
        root.addSubview(canvas)
        canvas.wantsLayer = true
        canvas.addSubview(backdrop)
        canvas.addSubview(glow)
        backdrop.shapeLayer.fillColor = NSColor.black.cgColor
        // The halo: a shadow of the light's colour, 4 points down and blurred over 10.
        backdrop.shapeLayer.shadowRadius = 5
        backdrop.shapeLayer.shadowOffset = CGSize(width: 0, height: -4)
        backdrop.shapeLayer.shadowOpacity = 0
        content.wantsLayer = true
        content.layer?.mask = mask
        canvas.addSubview(content)
        content.addSubview(text)
        canvas.onHover = { [weak state] inside in state?.isHovering = inside }
    }

    func refresh() {
        guard let screen = Screens.notch else { return }
        let notch = NotchMetrics.resolve(
            screenWidth: screen.frame.width,
            safeAreaTop: screen.safeAreaInsets.top,
            leftAreaWidth: screen.auxiliaryTopLeftArea?.width,
            rightAreaWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY
        )
        let style = PrompterStyle.current(notch: true)
        // Exactly the lines chosen, seen through a long fade at each edge: the line being read is the one lit in
        // full, a little above the middle; the one just read fades out upwards, the next ones into the lower edge.
        let textHeight = (style.lineHeight * CGFloat(PrompterPreferences.notchLines)).rounded()
        let layout = PrompterLayout(notch: notch, width: PrompterPreferences.notchWidth, textHeight: textHeight)
        self.layout = layout
        panel.sharingType = PrompterPreferences.hiddenFromCapture ? .none : .readOnly
        let size = layout.canvasSize
        panel.setFrame(NSRect(
            x: (screen.frame.minX + notch.centerX - size.width / 2).rounded(),
            y: screen.frame.maxY - size.height,
            width: size.width, height: size.height
        ), display: false)
        let bounds = NSRect(origin: .zero, size: size)
        canvas.frame = bounds
        backdrop.frame = bounds
        glow.frame = bounds
        content.frame = bounds
        mask.frame = bounds
        text.frame = flipped(layout.textFrame, in: size)
        text.fadeTop = (textHeight * 0.3).rounded()
        text.fadeBottom = (textHeight * 0.475).rounded()
        text.hiddenTop = 0
        text.readingInset = max(0, (textHeight * 0.41 - style.lineHeight / 2).rounded())
        text.horizontalInset = 18
        text.showsBand = false
        installOverlays(layout: layout, size: size)
        let path = outline(open: isOpen)
        glow.configure(body: flipped(layout.bodyFrame, in: size))
        glow.setColors(PrompterPreferences.stageLight)
        let light = PrompterPreferences.stageLight
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.shapeLayer.path = path
        backdrop.shapeLayer.shadowPath = path
        backdrop.shapeLayer.shadowColor = light == .off ? NSColor.black.cgColor : StageTheme.lamp(light).cgColor
        haloOpacity = light == .off ? 0.3 : 0.25
        if isOpen { backdrop.shapeLayer.shadowOpacity = haloOpacity }
        mask.path = path
        glow.outline.path = path
        CATransaction.commit()
        canvas.trackedRect = flipped(layout.frameOfOpenShape, in: size)
    }

    private func installOverlays(layout: PrompterLayout, size: CGSize) {
        overlay?.removeFromSuperview()
        let overlay = PassthroughHostingView(rootView: PrompterOverlay(state: state, showsStatusRow: false, scale: 0.8))
        overlay.sizingOptions = []
        overlay.frame = text.frame
        let state = self.state
        overlay.interactiveRects = { [weak overlay] in
            guard let overlay else { return [] }
            if state.failure != nil || state.summary != nil { return [overlay.bounds] }
            guard state.isHovering else { return [] }
            // The hosting view is flipped: the controls sit along its bottom edge, at the largest y.
            return [NSRect(x: overlay.bounds.midX - 90, y: overlay.bounds.maxY - 48, width: 180, height: 48)]
        }
        content.addSubview(overlay)
        self.overlay = overlay
        wings.forEach { $0.removeFromSuperview() }
        let frames = layout.wingFrames
        wings = [(CameraWing.Side.time, frames.left), (.voice, frames.right)].map { side, frame in
            let wing = NSHostingView(rootView: CameraWing(side: side, state: state))
            wing.sizingOptions = []
            wing.frame = flipped(frame, in: size)
            content.addSubview(wing)
            return wing
        }
    }

    func present() {
        refresh()
        content.alphaValue = 0
        panel.orderFrontRegardless()
        isOpen = true
        morph(open: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            content.animator().alphaValue = 1
        }
    }

    func glow(_ intensity: CGFloat) {
        glow.setIntensity(intensity)
    }

    func closeNow() {
        isOpen = false
        state.isHovering = false
        glow.setIntensity(0, duration: 0)
        panel.orderOut(nil)
        text.halt()
    }

    func dismiss(completion: @escaping @MainActor () -> Void) {
        isOpen = false
        state.isHovering = false
        glow.setIntensity(0, duration: 0.15)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            content.animator().alphaValue = 0
        }
        // Held until the motion ends: the controller has already let go of this presentation.
        morph(open: false) {
            self.panel.orderOut(nil)
            self.text.halt()
            completion()
        }
    }

    private func morph(open: Bool, completion: (@MainActor () -> Void)? = nil) {
        let path = outline(open: open)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion?() } }
        for (layer, key, target) in [(backdrop.shapeLayer, "path", path), (backdrop.shapeLayer, "shadowPath", path), (mask, "path", path), (glow.outline, "path", path)] {
            let animation = Motion.spring(open: open)
            animation.keyPath = key
            let current = key == "path" ? (layer.presentation()?.path ?? layer.path) : (layer.presentation()?.shadowPath ?? layer.shadowPath)
            animation.fromValue = current
            animation.toValue = target
            if key == "path" { layer.path = target } else { layer.shadowPath = target }
            layer.add(animation, forKey: key)
        }
        let shadow = Motion.spring(open: open)
        shadow.keyPath = "shadowOpacity"
        shadow.fromValue = backdrop.shapeLayer.presentation()?.shadowOpacity ?? backdrop.shapeLayer.shadowOpacity
        shadow.toValue = open ? haloOpacity : 0
        backdrop.shapeLayer.shadowOpacity = open ? haloOpacity : 0
        backdrop.shapeLayer.add(shadow, forKey: "shadowOpacity")
        CATransaction.commit()
    }

    private func outline(open: Bool) -> CGPath {
        guard let layout else { return CGMutablePath() }
        let size = layout.canvasSize
        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
        let path = PrompterPath.make(layout.shape(open: open), centerX: size.width / 2)
        return path.copy(using: &flip) ?? path
    }

    private func flipped(_ rect: CGRect, in size: CGSize) -> NSRect {
        NSRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height)
    }
}

extension PrompterLayout {
    /// The open outline's bounding box in the canvas, top-left origin.
    var frameOfOpenShape: CGRect {
        let open = shape(open: true)
        return CGRect(x: (canvasSize.width - open.outerWidth) / 2, y: 0, width: open.outerWidth, height: open.height)
    }
}

/// The notch canvas: reports the pointer over the open prompter.
final class NotchCanvas: NSView {
    var onHover: ((Bool) -> Void)?
    var trackedRect: NSRect = .zero {
        didSet {
            if let area { removeTrackingArea(area) }
            let area = NSTrackingArea(rect: trackedRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
            addTrackingArea(area)
            self.area = area
        }
    }
    private var area: NSTrackingArea?

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// The prompter's springs: opening overshoots a little, like something with weight; closing settles without a bounce.
@MainActor
enum Motion {
    static func spring(open: Bool) -> CABasicAnimation {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let fade = CABasicAnimation()
            fade.duration = 0.2
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            return fade
        }
        let spring = open
            ? CASpringAnimation(perceptualDuration: 0.55, bounce: 0.2)
            : CASpringAnimation(perceptualDuration: 0.4, bounce: 0)
        spring.duration = spring.settlingDuration
        return spring
    }
}
