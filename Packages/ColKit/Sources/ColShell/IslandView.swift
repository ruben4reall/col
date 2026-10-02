import AppKit
import ColCore
import SwiftUI

/// Draws the island on a canvas big enough for all its states, pinned to the top centre of the panel. The panel
/// shrinks and grows around it and re-pins the canvas each time, so on screen the canvas never moves and resizing
/// the window is invisible.
///
/// Three layers, all clipped by the island's outline: the black backdrop, the compact wings (Core Animation only),
/// and the open content (SwiftUI, created when the island opens and torn down once it has closed, so a closed
/// island holds no view tree at all).
///
/// With glass (macOS 26 and later) the backdrop is split in two: glass under the open island, and over it a black
/// that stays solid across the camera row, where the island meets the notch, then thins toward the lower edge. The
/// glass is Liquid Glass with its lens turned on (Liquid), a light blur of the desktop (Transparent) or Liquid Glass as
/// macOS draws it (Tinted).
final class IslandView: NSView {
    var onEvent: ((IslandEvent) -> Void)?
    let compact = CompactRenderer()

    private let backdrop = ShapeView()
    /// The glass under the open island. It only exists while the setting asks for it, and only draws while the island
    /// is open or moving, so a closed island costs nothing more than before.
    private let glassHost = PassthroughView()
    private let glassMask = CAShapeLayer()
    private var liquidGlass: NSView?
    private var clearGlass: CALayer?
    /// The island's black when it has glass under it, and, with Transparent glass, a light line along its lower edge.
    private let fade = GradientView()
    private let fadeMask = CAShapeLayer()
    private let edge = CAShapeLayer()
    private let edgeFade = CAGradientLayer()
    private var glassRequested: IslandGlass = .off
    private var glassStyle: IslandGlass = .off
    private var usesGlass: Bool { glassStyle != .off }
    private var targetState: IslandState = .collapsed
    private let contentContainer = NSView()
    private let compactView = NSView()
    private let contentMask = CAShapeLayer()
    let contentModel = IslandContentModel()
    private let services: IslandServices
    /// Horizontal two-finger swipes on the open island turn pages.
    var onPageSwipe: ((Int) -> Void)?
    /// Sideways swipes on the closed island: the next or previous track.
    var onCompactSwipe: ((Int) -> Void)?
    /// Files dragged over the island, and dropped on it.
    var onDragChange: ((Bool) -> Void)?
    var onDrop: (([URL]) -> Void)?
    private var hostingView: NSHostingView<IslandContentView>?
    private var layout: IslandLayout?
    private var trackingArea: NSTrackingArea?
    private var trackedRect: NSRect = .zero
    private var swipeTravel: CGFloat = 0
    private var sideTravel: CGFloat = 0
    private var swipeConsumed = false
    private let shadowOpacity: Float = 0.45
    /// A lighter shadow than the black island's, which would darken the glass from below.
    private let glassShadowOpacity: Float = 0.15
    private var openShadowOpacity: Float { usesGlass ? glassShadowOpacity : shadowOpacity }

    init(services: IslandServices) {
        self.services = services
        super.init(frame: .zero)
        wantsLayer = true

        let shape = backdrop.shapeLayer
        shape.fillColor = NSColor.black.cgColor
        shape.shadowColor = NSColor.black.cgColor
        shape.shadowOpacity = 0
        // Kept inside the window's margin (IslandLayout.shadowMargin): a shadow cut by the window edge draws a hard line.
        shape.shadowRadius = 11
        shape.shadowOffset = CGSize(width: 0, height: -4)
        addSubview(backdrop)

        glassHost.layer?.mask = glassMask
        glassHost.isHidden = true
        addSubview(glassHost)
        fade.layer?.mask = fadeMask
        fade.isHidden = true
        addSubview(fade)
        edge.fillColor = nil
        edge.strokeColor = NSColor.white.withAlphaComponent(0.35).cgColor
        // Centred on the outline, which clips it: one point shows, inside the island.
        edge.lineWidth = 2
        edge.mask = edgeFade
        edge.isHidden = true
        fade.layer?.addSublayer(edge)

        contentContainer.wantsLayer = true
        contentContainer.layer?.mask = contentMask
        addSubview(contentContainer)

        compactView.wantsLayer = true
        compactView.layer?.addSublayer(compact.layer)
        contentContainer.addSubview(compactView)
        registerForDraggedTypes([.fileURL])
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyGlass() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Layout

    /// Sizes the canvas for a screen and draws the island without animating.
    func configure(_ layout: IslandLayout, state: IslandState, wings: Wings, scale: CGFloat) {
        self.layout = layout
        let canvas = NSRect(origin: .zero, size: layout.canvasSize)
        frame.size = canvas.size
        for view in [backdrop, glassHost, fade, contentContainer, compactView] { view.frame = canvas }
        for mask in [contentMask, glassMask, fadeMask] { mask.frame = canvas }
        edge.frame = canvas
        edgeFade.frame = canvas
        compact.layer.frame = canvas
        compact.setScale(scale)
        contentModel.notchWidth = layout.notch.width
        contentModel.notchHeight = layout.notch.height
        hostingView?.frame = flipped(layout.contentFrame)
        placeGlass(layout)
        layOutFade(layout)
        targetState = state

        let path = outline(for: state, wings: wings, in: layout)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.shapeLayer.path = path
        backdrop.shapeLayer.shadowPath = path
        backdrop.shapeLayer.shadowOpacity = state == .expanded ? openShadowOpacity : 0
        contentMask.path = path
        glassMask.path = path
        fadeMask.path = path
        edge.path = path
        CATransaction.commit()
        glassHost.isHidden = !(usesGlass && state == .expanded)
        setIdleVisibility(state: state, wings: wings, animated: false)
        track(state, wings: wings)
    }

    /// A floating island (no notch) has nothing to hide behind: idle and closed, it fades away entirely and only
    /// its hover area stays.
    private func setIdleVisibility(state: IslandState, wings: Wings, animated: Bool) {
        guard let layout else { return }
        let hidden = !layout.notch.isHardware && state == .collapsed && wings.isEmpty
        let target: Float = hidden ? 0 : 1
        for layer in [backdrop.layer, glassHost.layer, fade.layer, contentContainer.layer].compactMap({ $0 }) where layer.opacity != target {
            if animated {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
                fade.toValue = target
                fade.duration = hidden ? 0.25 : 0.15
                layer.add(fade, forKey: "idle")
            }
            layer.opacity = target
        }
    }

    /// Morphs the island to `state` with `wings`. `completion` runs once the motion has settled.
    func transition(to state: IslandState, wings: Wings, completion: @escaping @MainActor () -> Void) {
        guard let layout else { return }
        setIdleVisibility(state: state, wings: wings, animated: true)
        let path = outline(for: state, wings: wings, in: layout)
        targetState = state
        // The glass grows with the island as it opens, and goes back to sleep once it has closed.
        if usesGlass, state == .expanded {
            glassHost.isHidden = false
            retuneLiquid()
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                if let self, self.targetState != .expanded { self.glassHost.isHidden = true }
                completion()
            }
        }
        animate(backdrop.shapeLayer, \.path, "path", to: path, toward: state)
        animate(backdrop.shapeLayer, \.shadowPath, "shadowPath", to: path, toward: state)
        animate(contentMask, \.path, "path", to: path, toward: state)
        animate(glassMask, \.path, "path", to: path, toward: state)
        animate(fadeMask, \.path, "path", to: path, toward: state)
        animate(edge, \.path, "path", to: path, toward: state)
        let opacity: Float = state == .expanded ? openShadowOpacity : 0
        let shadow = Motion.animation(toward: state)
        shadow.keyPath = "shadowOpacity"
        shadow.fromValue = backdrop.shapeLayer.presentation()?.shadowOpacity ?? backdrop.shapeLayer.shadowOpacity
        shadow.toValue = opacity
        backdrop.shapeLayer.shadowOpacity = opacity
        backdrop.shapeLayer.add(shadow, forKey: "shadowOpacity")
        CATransaction.commit()

        track(state, wings: wings)
    }

    func showCompact(_ presentation: CompactPresentation?, wings: Wings) {
        guard let layout else { return }
        compact.show(presentation, layout: layout, wings: wings, canvasHeight: layout.canvasSize.height)
    }

    private func animate(
        _ layer: CAShapeLayer,
        _ property: ReferenceWritableKeyPath<CAShapeLayer, CGPath?>,
        _ key: String,
        to path: CGPath,
        toward state: IslandState
    ) {
        let animation = Motion.animation(toward: state)
        animation.keyPath = key
        // Start from what is on screen, so a transition that interrupts another picks up mid-flight.
        animation.fromValue = layer.presentation()?[keyPath: property] ?? layer[keyPath: property]
        animation.toValue = path
        layer[keyPath: property] = path
        layer.add(animation, forKey: key)
    }

    private func outline(for state: IslandState, wings: Wings, in layout: IslandLayout) -> CGPath {
        let canvas = layout.canvasSize
        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: canvas.height)
        let shape = layout.shape(for: state, wings: wings)
        let path = IslandPath.make(shape, centerX: canvas.width / 2 + shape.offset)
        return path.copy(using: &flip) ?? path
    }

    // MARK: Glass

    static var glassAvailable: Bool {
        if #available(macOS 26.0, *) { true } else { false }
    }

    /// Sets the glass. It needs macOS 26, and stays off while the system reduces transparency.
    func setGlass(_ style: IslandGlass) {
        glassRequested = style
        applyGlass()
    }

    private func applyGlass() {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        var style = Self.glassAvailable && !reduced ? glassRequested : .off
        if style != glassStyle || (style != .off && liquidGlass == nil && clearGlass == nil) {
            liquidGlass?.removeFromSuperview()
            liquidGlass = nil
            clearGlass?.removeFromSuperlayer()
            clearGlass = nil
            if style == .transparent {
                if let layer = Backdrop.make(blur: 3, brightness: -0.25, saturation: 1.3) {
                    glassHost.layer?.addSublayer(layer)
                    clearGlass = layer
                } else {
                    style = .tinted
                }
            }
            if style == .liquid || style == .tinted, #available(macOS 26.0, *) {
                let view = NSGlassEffectView()
                // Clear Liquid Glass: the black above it already keeps the content readable.
                view.style = .clear
                // A touch less round than the island's corners, so the island's outline always trims the glass.
                view.cornerRadius = 28
                glassHost.addSubview(view)
                liquidGlass = view
            }
        }
        glassStyle = style
        if let layout {
            placeGlass(layout)
            layOutFade(layout)
        }
        retuneLiquid()
        backdrop.shapeLayer.fillColor = usesGlass ? NSColor.clear.cgColor : NSColor.black.cgColor
        if targetState == .expanded { backdrop.shapeLayer.shadowOpacity = openShadowOpacity }
        fade.isHidden = !usesGlass
        edge.isHidden = glassStyle != .transparent
        glassHost.isHidden = !(usesGlass && targetState == .expanded)
    }

    /// The Liquid look: Apple's glass with its frost almost gone and its lens turned on, so what lies behind is
    /// magnified and bent along the edges. The white of the glass is held a little below white, so the island's own
    /// white stays readable over a white window.
    private static let liquidTuning: [String: Double] = [
        "inputBlurRadius": 0,
        "inputRefractionOpacity": 1,
        "inputInnerRefractionAmount": -110,
        "inputInnerRefractionHeight": 30,
        "inputFaceColorMatrixWhite": 0.8,
    ]

    /// macOS builds the glass's layers lazily and may rebuild them, so the tuning is applied again whenever the island
    /// opens or the appearance changes.
    private func retuneLiquid() {
        guard glassStyle == .liquid, let liquidGlass else { return }
        LiquidGlassTuning.apply(Self.liquidTuning, to: liquidGlass)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.glassStyle == .liquid, let glass = self.liquidGlass else { return }
            LiquidGlassTuning.apply(Self.liquidTuning, to: glass)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        retuneLiquid()
    }

    /// Both kinds of glass cover the open island's body; its outline trims them.
    private func placeGlass(_ layout: IslandLayout) {
        let frame = flipped(layout.contentFrame)
        liquidGlass?.frame = frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clearGlass?.frame = frame
        CATransaction.commit()
    }

    /// How much black is left at the open island's lower edge. Liquid Glass keeps a little, so white controls stay
    /// readable over a white window; the Transparent glass dims what it shows instead.
    static func fadeFloor(for style: IslandGlass) -> CGFloat { style == .tinted ? 0.12 : 0 }

    /// Where the black starts to thin: below everything the closed island ever covers and below the camera row.
    private static func solidDepth(_ layout: IslandLayout) -> CGFloat {
        let open = layout.frame(for: .expanded)
        let closed = max(layout.frame(for: .peek).maxY, layout.frame(for: .collapsed, wings: Wings(IslandLayout.maximumWing)).maxY)
        return max(closed, open.minY + layout.notch.height) + 16
    }

    /// The black over the glass, from the top of the canvas down: solid down to `solidDepth`, then thinner and thinner
    /// to the open island's lower edge, eased so the glass rises out of the black without a visible band. `y` is
    /// measured from the top of the canvas.
    static func fadeStops(for layout: IslandLayout, style: IslandGlass) -> [(y: CGFloat, alpha: CGFloat)] {
        let bottom = layout.frame(for: .expanded).maxY
        let solid = solidDepth(layout)
        let floor = fadeFloor(for: style)
        var stops: [(y: CGFloat, alpha: CGFloat)] = [(y: 0, alpha: 1)]
        let steps = 10
        // The glass is reached three quarters of the way down, so the island's last stretch is glass throughout.
        let reached = solid + (bottom - solid) * 0.75
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let eased = t * t * (3 - 2 * t)
            stops.append((y: solid + (reached - solid) * t, alpha: 1 - (1 - floor) * eased))
        }
        stops.append((y: bottom, alpha: floor))
        return stops
    }

    private func layOutFade(_ layout: IslandLayout) {
        let height = layout.canvasSize.height
        let stops = Self.fadeStops(for: layout, style: glassStyle)
        let gradient = fade.gradientLayer
        gradient.colors = stops.map { NSColor.black.withAlphaComponent($0.alpha).cgColor }
        gradient.locations = stops.map { NSNumber(value: Double(min(max($0.y / height, 0), 1))) }
        // Top to bottom: the layer's origin is its lower left corner.
        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        // The edge lights up only where the island has become glass.
        let bottom = layout.frame(for: .expanded).maxY
        let solid = Self.solidDepth(layout)
        edgeFade.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor, NSColor.white.cgColor]
        edgeFade.locations = [0, NSNumber(value: Double((solid + (bottom - solid) * 0.35) / height)), NSNumber(value: Double(bottom / height))]
        edgeFade.startPoint = CGPoint(x: 0.5, y: 1)
        edgeFade.endPoint = CGPoint(x: 0.5, y: 0)
    }

    /// Converts a top-left canvas rect into the view's bottom-left space.
    private func flipped(_ rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: Content

    func presentContent() {
        guard let layout else { return }
        if hostingView == nil {
            let hosting = NSHostingView(rootView: IslandContentView(model: contentModel, services: services))
            hosting.sizingOptions = []
            hosting.frame = flipped(layout.contentFrame)
            contentContainer.addSubview(hosting)
            hostingView = hosting
        }
        compact.setVisible(false, animated: true)
        // Next turn of the run loop, so SwiftUI sees the change and animates the entrance.
        DispatchQueue.main.async { [contentModel] in contentModel.isPresented = true }
    }

    func dismissContent() {
        contentModel.isPresented = false
        compact.setVisible(true, animated: true)
    }

    func discardContent() {
        hostingView?.removeFromSuperview()
        hostingView = nil
    }

    // MARK: Pointer

    /// Watches the pointer over the shape a state will have. Replacing a tracking area does not say whether the
    /// pointer is already inside; `containsPointer` does.
    private func track(_ state: IslandState, wings: Wings) {
        guard let layout else { return }
        if let trackingArea { removeTrackingArea(trackingArea) }
        trackedRect = flipped(layout.frame(for: state, wings: wings))
        let area = NSTrackingArea(rect: trackedRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    var containsPointer: Bool {
        guard let window else { return false }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        return trackedRect.contains(point)
    }

    // MARK: Drops

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard Self.fileURLs(in: sender).isEmpty == false else { return [] }
        onDragChange?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragChange?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = Self.fileURLs(in: sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    private static func fileURLs(in info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    override func mouseEntered(with event: NSEvent) { onEvent?(.pointerEntered) }
    override func mouseExited(with event: NSEvent) { onEvent?(.pointerExited) }
    override func mouseDown(with event: NSEvent) { onEvent?(.pressed) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let settings = NSMenuItem(title: String(localized: "Settings…", bundle: .module), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        if Updates.checker != nil {
            let update = NSMenuItem(title: String(localized: "Check for Updates…", bundle: .module), action: #selector(checkForUpdates), keyEquivalent: "")
            update.target = self
            menu.addItem(update)
        }
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "Quit Col", bundle: .module),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func openSettings() {
        SettingsWindow.shared.show()
    }

    @objc private func checkForUpdates() {
        Updates.checker?.checkForUpdates()
    }

    /// Two fingers down opens, two fingers up closes. One gesture triggers at most once, and the inertia that
    /// follows a flick is ignored.
    override func scrollWheel(with event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        if event.phase.contains(.began) || event.phase.isEmpty {
            swipeTravel = 0
            sideTravel = 0
            swipeConsumed = false
        }
        // Sideways on the closed island: change track.
        if hostingView == nil, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            let delta = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaX : event.scrollingDeltaX
            sideTravel += event.hasPreciseScrollingDeltas ? delta : delta * 10
            if !swipeConsumed, abs(sideTravel) >= 40 {
                swipeConsumed = true
                onCompactSwipe?(sideTravel > 0 ? 1 : -1)
            }
            return
        }
        // Sideways on the open island: turn the page.
        if hostingView != nil, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            // Positive when the fingers move left, which brings the next page in, as on a phone.
            let delta = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaX : event.scrollingDeltaX
            sideTravel += event.hasPreciseScrollingDeltas ? delta : delta * 10
            if !swipeConsumed, abs(sideTravel) >= 40 {
                swipeConsumed = true
                onPageSwipe?(sideTravel > 0 ? 1 : -1)
            }
            return
        }
        // Positive when the fingers move down, whatever the natural scrolling setting.
        let delta = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
        swipeTravel += event.hasPreciseScrollingDeltas ? delta : delta * 10
        if !swipeConsumed, abs(swipeTravel) >= 18 {
            swipeConsumed = true
            onEvent?(swipeTravel > 0 ? .swipedDown : .swipedUp)
        }
    }
}

/// A view that never takes the pointer: the island's content and the island itself handle it.
final class PassthroughView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A view backed directly by a gradient layer.
final class GradientView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func makeBackingLayer() -> CALayer { CAGradientLayer() }

    // swiftlint:disable:next force_cast
    var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A view backed directly by a shape layer.
final class ShapeView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func makeBackingLayer() -> CALayer { CAShapeLayer() }

    // swiftlint:disable:next force_cast
    var shapeLayer: CAShapeLayer { layer as! CAShapeLayer }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
