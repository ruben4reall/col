import AppKit
import IsletCore
import SwiftUI

/// The real island inside a window: the same view that draws the one in the notch, at its real size, over the user's
/// own wallpaper cut around their notch, showing what the island shows right now. It opens when the pointer rests on
/// it and closes when the pointer leaves, by the same rules as the notch. Nothing here is a drawing of the island.
struct IslandStage: NSViewRepresentable {
    let size: IslandSize
    let glass: IslandGlass
    /// Opens the island as the stage appears, so the open size shows at once.
    var opensOnAppear = true
    /// Bumped to replay the opening, after a setting changed.
    var replay = 0
    /// Pages to show instead of the user's, such as a deck being edited, and the page to show: a page's id, or "live"
    /// for the Live page.
    var deck: PageDeck?
    var page: String?
    /// Agents of the stage's own, for an example request that must not reach the real ones.
    var agents: AgentCenter?

    /// The open island, its shadow and some wallpaper below it.
    static func height(for size: IslandSize) -> CGFloat {
        IslandStageView.notchHeight + size.open.content + 58
    }

    func makeNSView(context: Context) -> IslandStageView {
        IslandStageView(opensOnAppear: opensOnAppear, agents: agents)
    }

    func updateNSView(_ view: IslandStageView, context: Context) {
        view.update(size: size, glass: glass, replay: replay)
        view.show(deck: deck, page: page)
    }

    static func dismantleNSView(_ view: IslandStageView, coordinator: ()) {
        view.tearDown()
    }
}

@MainActor
final class IslandStageView: NSView {
    /// The notch the stage reproduces: the island's own, or a common one when no island runs.
    static var notch: NotchMetrics {
        IslandController.shared?.notchMetrics ?? NotchMetrics(width: 185, height: 32, centerX: 756, isHardware: true)
    }

    static var notchHeight: CGFloat { notch.height }

    private let wallpaper = CALayer()
    /// Holds the island; its bounds shrink the island when the stage is narrower than it.
    private let scaler = NSView()
    private var island: IslandView?
    private let navigation = IslandNavigation()
    private var machine = IslandMachine(opensOnHover: true)
    private var islandLayout: IslandLayout?
    private var size: IslandSize?
    private var glass: IslandGlass = .off
    private var replay = 0
    private let opensOnAppear: Bool
    private var opened = false
    private var hoverTimer: Task<Void, Never>?
    private var exitTimer: Task<Void, Never>?
    private var generation = 0
    private var wallpaperImage: CGImage?

    init(opensOnAppear: Bool, agents: AgentCenter? = nil) {
        self.opensOnAppear = opensOnAppear
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor
        wallpaper.contentsGravity = .resize
        layer?.addSublayer(wallpaper)
        scaler.wantsLayer = true
        addSubview(scaler)
        if let services = IslandController.shared?.stageServices(navigation: navigation, agents: agents) {
            let island = IslandView(services: services)
            island.onEvent = { [weak self] event in self?.send(event) }
            island.onPageSwipe = { [weak self] step in self?.navigation.step(step) }
            scaler.addSubview(island)
            self.island = island
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(size: IslandSize, glass: IslandGlass, replay: Int) {
        if glass != self.glass {
            self.glass = glass
            island?.setGlass(glass)
        }
        let resized = size != self.size
        if resized {
            let first = self.size == nil
            self.size = size
            // A new size closes the island, takes the size while it is closed, and opens again.
            if first || machine.state != .expanded { configure() } else { reopen(resizing: true) }
        }
        if replay != self.replay {
            self.replay = replay
            if !resized { reopen(resizing: false) }
        }
    }

    /// Shows a page, from a deck of its own or from the user's.
    func show(deck: PageDeck?, page: String?) {
        if let deck { navigation.use(deck) }
        guard let page else { return }
        if page == "live" {
            if navigation.route != .live { navigation.show(.live) }
        } else if navigation.route != .page(page) {
            navigation.show(.page(page))
        }
    }

    /// Stops the timers and lets go of the island's content.
    func tearDown() {
        hoverTimer?.cancel()
        exitTimer?.cancel()
        island?.dismissContent()
        island?.discardContent()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        configure()
        loadWallpaper()
        if opensOnAppear, !opened {
            opened = true
            // A beat after the pane appears, so the opening is seen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                MainActor.assumeIsolated { self?.send(.requested) }
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        wallpaperImage = nil
        loadWallpaper()
    }

    // MARK: Layout

    private func configure() {
        guard let island, let size, window != nil else { return }
        let layout = IslandLayout(notch: Self.notch, size: size)
        islandLayout = layout
        let wings = machine.state == .expanded ? Wings.none : compactWings
        island.configure(layout, state: machine.state, wings: wings, scale: window?.backingScaleFactor ?? 2)
        island.setGlass(glass)
        showCompact()
        if machine.state == .expanded {
            island.presentContent()
        }
        needsLayout = true
    }

    private var scale: CGFloat {
        guard let layout = islandLayout else { return 1 }
        let island = layout.frame(for: .expanded).width + 24
        return min(1, bounds.width / island)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wallpaper.frame = bounds
        CATransaction.commit()
        guard let layout = islandLayout, let island else { return }
        let canvas = layout.canvasSize
        let scale = self.scale
        scaler.frame = NSRect(
            x: ((bounds.width - canvas.width * scale) / 2).rounded(),
            y: bounds.height - canvas.height * scale,
            width: canvas.width * scale,
            height: canvas.height * scale
        )
        scaler.bounds = NSRect(origin: .zero, size: canvas)
        island.frame = NSRect(origin: .zero, size: canvas)
        cropWallpaper()
    }

    // MARK: The wallpaper

    private func loadWallpaper() {
        guard wallpaperImage == nil, let screen = IslandController.shared?.screenForPreview ?? NSScreen.main else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        wallpaperImage = DesktopPicture.image(for: screen, dark: dark)
        cropWallpaper()
    }

    /// The part of the wallpaper that sits around the notch on the real screen, at the stage's scale. macOS fills the
    /// screen with the picture, centred, cropping what overflows: the same rule places it here.
    private func cropWallpaper() {
        guard let image = wallpaperImage, let screen = IslandController.shared?.screenForPreview ?? NSScreen.main, bounds.width > 0 else { return }
        let screenSize = screen.frame.size
        let pointsPerPixel = max(screenSize.width / CGFloat(image.width), screenSize.height / CGFloat(image.height))
        let drawn = CGSize(width: CGFloat(image.width) * pointsPerPixel, height: CGFloat(image.height) * pointsPerPixel)
        let origin = CGPoint(x: (screenSize.width - drawn.width) / 2, y: (screenSize.height - drawn.height) / 2)
        let scale = self.scale
        let region = CGRect(
            x: Self.notch.centerX - bounds.width / scale / 2, y: 0,
            width: bounds.width / scale, height: bounds.height / scale
        )
        let pixels = CGRect(
            x: (region.minX - origin.x) / pointsPerPixel, y: (region.minY - origin.y) / pointsPerPixel,
            width: region.width / pointsPerPixel, height: region.height / pointsPerPixel
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wallpaper.contents = image.cropping(to: pixels)
        CATransaction.commit()
    }

    // MARK: Behaviour, as in the notch

    private var compactWings: Wings {
        IslandController.shared?.compactNow.wings ?? .none
    }

    private func showCompact() {
        guard let island, let controller = IslandController.shared else { return }
        for (key, image) in controller.compactImages { island.compact.register(image, for: key) }
        let now = controller.compactNow
        island.showCompact(machine.state == .expanded ? nil : now.presentation, wings: machine.state == .expanded ? .none : now.wings)
    }

    /// Closes and opens again, to show a change of size or glass.
    private func reopen(resizing: Bool) {
        guard machine.state == .expanded else {
            if resizing { configure() }
            send(.requested)
            return
        }
        send(.dismissed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if resizing { self.configure() }
                self.send(.requested)
            }
        }
    }

    private func send(_ event: IslandEvent) {
        let previous = machine.state
        let effects = machine.handle(event)
        for effect in effects {
            switch effect {
            case .startHoverTimer:
                hoverTimer?.cancel()
                hoverTimer = after(Motion.hoverDwell) { $0.send(.hoverTimerFired) }
            case .cancelHoverTimer:
                hoverTimer?.cancel()
            case .startExitTimer:
                exitTimer?.cancel()
                exitTimer = after(Motion.exitGrace) { $0.send(.exitTimerFired) }
            case .cancelExitTimer:
                exitTimer?.cancel()
            case .haptic:
                break
            }
        }
        if machine.state != previous { reshape(from: previous) }
    }

    private func after(_ delay: Duration, _ action: @escaping @MainActor (IslandStageView) -> Void) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            action(self)
        }
    }

    private func reshape(from previous: IslandState) {
        guard let island else { return }
        generation += 1
        let current = generation
        let state = machine.state
        let wings = state == .expanded ? Wings.none : compactWings
        if state == .expanded, previous != .expanded {
            island.presentContent()
        }
        if previous == .expanded, state != .expanded {
            island.dismissContent()
        }
        island.showCompact(state == .expanded ? nil : IslandController.shared?.compactNow.presentation, wings: wings)
        island.transition(to: state, wings: wings) { [weak self] in
            guard let self, self.generation == current else { return }
            if state != .expanded { self.island?.discardContent() }
        }
    }
}
