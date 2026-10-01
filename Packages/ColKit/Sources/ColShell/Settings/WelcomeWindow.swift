import AppKit
import CoreBluetooth
import EventKit
import ColCore
import Observation
import ServiceManagement
import SwiftUI

/// The first-launch welcome. The island greets first, from the notch; then this window is born out of the island, teaches
/// the gestures on the real notch, lets the user pick modules, and asks only for the permissions those modules need.
/// When it is done, it goes back into the notch and the island says it is ready.
@MainActor
final class WelcomeWindow: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindow()
    private var window: NSWindow?
    /// The rounded card the window shows; the window around it is transparent.
    private var card: NSView?
    private var content: NSView?
    private(set) var model: WelcomeModel?
    private static let key = "hasWelcomed"
    static let size = NSSize(width: 640, height: 560)
    private static let radius: CGFloat = 26
    private static let dark = NSColor(srgbRed: 0.05, green: 0.05, blue: 0.055, alpha: 1)

    static var hasWelcomed: Bool { UserDefaults.standard.bool(forKey: key) }

    private var still: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Shows the welcome. From the island, the window is born out of it: it starts as the open island, hidden behind
    /// it, and grows out from under it to its place below.
    func show(fromIsland: Bool = false) {
        if window == nil { makeWindow() }
        guard let window else { return }
        NSApp.activate()
        if fromIsland, !still, let island = IslandController.shared?.islandFrame(for: .expanded) {
            appear(window, from: island)
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func makeWindow() {
        let model = WelcomeModel()
        self.model = model
        let hosting = NSHostingView(rootView: WelcomeView(model: model) { [weak self] in self?.finish() })
        let window = WelcomePanel(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .fullSizeContentView],
                                  backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.delegate = self
        let container = NSView(frame: NSRect(origin: .zero, size: Self.size))
        container.wantsLayer = true
        let card = NSView(frame: container.bounds)
        card.wantsLayer = true
        card.layer?.cornerRadius = Self.radius
        card.layer?.cornerCurve = .continuous
        card.layer?.masksToBounds = true
        card.layer?.backgroundColor = Self.dark.cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor(white: 1, alpha: 0.1).cgColor
        hosting.frame = card.bounds
        hosting.autoresizingMask = [.width, .height]
        card.addSubview(hosting)
        container.addSubview(card)
        window.contentView = container
        WindowPlacement.belowIsland(window, preferred: Self.size, minimum: Self.size, sizeKey: "welcomeWindowFrame")
        self.window = window
        self.card = card
        self.content = hosting
    }

    // MARK: Born from the island, back into the notch

    /// The window reaches up to the top of the screen while the card travels, so the card can be drawn where the
    /// island is. Below the island and the menu bar, the card starts out hidden behind them.
    private func stretch(_ window: NSWindow, over rect: NSRect) -> NSRect {
        let frame = window.frame
        let top = (window.screen ?? NSScreen.main)?.frame.maxY ?? frame.maxY
        let minX = min(frame.minX, rect.minX), maxX = max(frame.maxX, rect.maxX)
        let tall = NSRect(x: minX, y: frame.minY, width: maxX - minX, height: top - frame.minY)
        window.setFrame(tall, display: false)
        return NSRect(x: frame.minX - tall.minX, y: 0, width: frame.width, height: frame.height)
    }

    /// The transform that draws the card's `rect` at `target`, both in the layer's own coordinates, for a layer that
    /// transforms its sublayers about its anchor point.
    private static func transform(from rect: NSRect, to target: NSRect, in layer: CALayer) -> CATransform3D {
        let sx = target.width / rect.width, sy = target.height / rect.height
        let pivot = CGPoint(x: layer.anchorPoint.x * layer.bounds.width, y: layer.anchorPoint.y * layer.bounds.height)
        let tx = target.minX - pivot.x + sx * (pivot.x - rect.minX)
        let ty = target.minY - pivot.y + sy * (pivot.y - rect.minY)
        return CATransform3DConcat(CATransform3DMakeScale(sx, sy, 1), CATransform3DMakeTranslation(tx, ty, 0))
    }

    private func appear(_ window: NSWindow, from island: NSRect) {
        guard let card, let content, let layer = window.contentView?.layer else { return window.makeKeyAndOrderFront(nil) }
        let final = window.frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.hasShadow = false
        let cardFrame = stretch(window, over: island)
        card.frame = cardFrame
        let start = NSRect(x: island.minX - window.frame.minX, y: island.minY - window.frame.minY, width: island.width, height: island.height)
        let from = Self.transform(from: cardFrame, to: start, in: layer)
        layer.sublayerTransform = CATransform3DIdentity
        content.alphaValue = 0
        CATransaction.commit()
        window.makeKeyAndOrderFront(nil)

        // The card grows out of the island, black as the island at first, its corners from the island's to its own.
        let grow = CASpringAnimation(perceptualDuration: 0.75, bounce: 0.1)
        grow.keyPath = "sublayerTransform"
        grow.fromValue = NSValue(caTransform3D: from)
        grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        grow.duration = grow.settlingDuration
        layer.add(grow, forKey: "birth")
        let colour = CABasicAnimation(keyPath: "backgroundColor")
        colour.fromValue = NSColor.black.cgColor
        colour.toValue = Self.dark.cgColor
        colour.duration = 0.5
        card.layer?.add(colour, forKey: "birth")
        let corner = CABasicAnimation(keyPath: "cornerRadius")
        corner.fromValue = Theme.islandCorner * cardFrame.width / island.width
        corner.toValue = Self.radius
        corner.duration = 0.55
        corner.timingFunction = CAMediaTimingFunction(name: .easeOut)
        card.layer?.add(corner, forKey: "corner")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { content.animator().alphaValue = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + grow.settlingDuration) { [weak self] in
            self?.settle(window, at: final)
        }
    }

    /// Back to a window the size of its card, its shadow on.
    private func settle(_ window: NSWindow, at frame: NSRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.setFrame(frame, display: true)
        card?.frame = NSRect(origin: .zero, size: frame.size)
        window.hasShadow = true
        CATransaction.commit()
        window.invalidateShadow()
    }

    /// The card shrinks back into the notch, fading to the island's black, and the window closes.
    private func goBack(then done: @escaping () -> Void) {
        guard let window, !still, let card, let content, let layer = window.contentView?.layer,
              let notch = IslandController.shared?.islandFrame(for: .collapsed)
        else {
            window?.close()
            return done()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.hasShadow = false
        let cardFrame = stretch(window, over: notch)
        card.frame = cardFrame
        CATransaction.commit()
        let target = NSRect(x: notch.minX - window.frame.minX, y: notch.minY - window.frame.minY, width: notch.width, height: notch.height)
        let to = Self.transform(from: cardFrame, to: target, in: layer)
        // Quick to leave, gentle as it reaches the notch; its colour turns to the island's black on the way.
        let duration = 0.6
        let shrink = CABasicAnimation(keyPath: "sublayerTransform")
        shrink.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
        shrink.toValue = NSValue(caTransform3D: to)
        shrink.duration = duration
        shrink.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
        layer.add(shrink, forKey: "back")
        layer.sublayerTransform = to
        let colour = CABasicAnimation(keyPath: "backgroundColor")
        colour.fromValue = Self.dark.cgColor
        colour.toValue = NSColor.black.cgColor
        colour.beginTime = CACurrentMediaTime() + duration * 0.35
        colour.duration = duration * 0.45
        colour.fillMode = .backwards
        card.layer?.add(colour, forKey: "back")
        card.layer?.backgroundColor = NSColor.black.cgColor
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            content.animator().alphaValue = 0
        }
        // The island starts to open as the card arrives, as if the card became it.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.75) { done() }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            window.orderOut(nil)
            window.close()
        }
    }

    /// The island reports the gestures, so the tutorial can tick them as they happen.
    func gesture(_ gesture: WelcomeModel.Gesture) {
        model?.done(gesture)
    }

    private func finish() {
        let launches = UserDefaults.standard.object(forKey: "welcomeLaunchAtLogin") as? Bool ?? true
        if launches { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        // Answered here, so Sparkle never has to ask about automatic checks in an alert of its own.
        Updates.checker?.automaticallyChecksForUpdates = UserDefaults.standard.object(forKey: "welcomeChecksForUpdates") as? Bool ?? true
        goBack { IslandController.shared?.sayReady() }
    }

    /// Escape, or Later: the welcome closes where it stands and comes back from the island's menu.
    func dismiss() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: Self.key)
        window?.emptyWhenClosed()
        window = nil
        card = nil
        content = nil
        model = nil
    }
}

/// The welcome's window: no title bar, its card drawn inside, so it can come out of the island and go back in.
final class WelcomePanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    /// While the card travels the window reaches the top of the screen: no constraint pushes it under the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
@Observable
final class WelcomeModel {
    enum Step: Int, CaseIterable {
        case discover, island, gestures, ready
    }

    enum Gesture {
        case hover, swipeDown, swipeSide
    }

    /// What Col can do. Each starts on when the Mac has what it needs.
    enum Feature: String, CaseIterable, Identifiable {
        case music, lyrics, headphones, ai, agents, agenda, prompter, hud, battery, privacy, shelf, clipboard, tools, system
        var id: String { rawValue }

        var title: Text {
            switch self {
            case .music: Text("Music", bundle: .module)
            case .lyrics: Text("Lyrics", bundle: .module)
            case .headphones: Text("Headphones", bundle: .module)
            case .ai: Text("AI apps", bundle: .module)
            case .agents: Text("Coding agents", bundle: .module)
            case .agenda: Text("Agenda", bundle: .module)
            case .prompter: Text("Prompter", bundle: .module)
            case .hud: Text("Volume and brightness", bundle: .module)
            case .battery: Text("Battery", bundle: .module)
            case .privacy: Text("Microphone and camera", bundle: .module)
            case .shelf: Text("Shelf", bundle: .module)
            case .clipboard: Text("Clipboard", bundle: .module)
            case .tools: Text("Tools", bundle: .module)
            case .system: Text("System", bundle: .module)
            }
        }

        var symbol: String {
            switch self {
            case .music: "music.note"
            case .lyrics: "quote.bubble.fill"
            case .headphones: "airpodspro"
            case .ai: "sparkles"
            case .agents: "chevron.left.forwardslash.chevron.right"
            case .agenda: "calendar"
            case .prompter: "text.alignleft"
            case .hud: "speaker.wave.2.fill"
            case .battery: "battery.75percent"
            case .privacy: "mic.fill"
            case .shelf: "tray.fill"
            case .clipboard: "doc.on.clipboard.fill"
            case .tools: "timer"
            case .system: "cpu"
            }
        }

        var tint: Color {
            switch self {
            case .music, .lyrics: Color(red: 0.98, green: 0.26, blue: 0.4)
            case .headphones, .shelf: .blue
            case .ai: Color(red: 0.45, green: 0.5, blue: 1)
            case .agents: .purple
            case .prompter: .orange
            case .agenda: .red
            case .hud: .gray
            case .battery: .green
            case .privacy, .tools: .orange
            case .clipboard: .indigo
            case .system: .teal
            }
        }
    }

    var step: Step = .discover
    private(set) var direction = 1
    private(set) var gestures: Set<Gesture> = []
    /// What the Mac has, looked at once as the welcome opens.
    let found: Discovery
    private(set) var features: Set<Feature>
    /// An example request from Claude Code, or from the first agent found, for the island shown here only: it never
    /// reaches the real agents.
    @ObservationIgnored let exampleAgents = AgentCenter()

    init() {
        let models = IslandController.shared?.models
        found = Discovery.look(ai: models?.ai, power: models?.power)
        features = found.suggested
        let agent = found.agents.first ?? .claude
        exampleAgents.receive(HookEvent(sessionID: "example", event: "UserPromptSubmit", cwd: "/Users/you/website", agent: agent)) { _ in }
        exampleAgents.receive(HookEvent(
            sessionID: "example", event: "PermissionRequest", cwd: "/Users/you/website", toolName: "Bash",
            toolInput: ["command": .string("npm test")], agent: agent
        )) { _ in }
    }

    /// The pages the island will have, from the features kept: Home first, then a page for each tool, in the order
    /// they matter.
    var deck: PageDeck {
        var deck = PageDeck(pages: [PageDeck.standard.pages[0]])
        let order: [(Feature, WidgetKind)] = [(.prompter, .prompter), (.ai, .ai), (.shelf, .shelf), (.clipboard, .clipboard), (.tools, .tools), (.system, .system)]
        for (feature, kind) in order where features.contains(feature) {
            deck.add([WidgetStack([kind])], id: kind.rawValue)
        }
        return deck
    }

    func go(_ step: Step) {
        direction = step.rawValue >= self.step.rawValue ? 1 : -1
        withAnimation(.spring(duration: 0.55, bounce: 0.16)) { self.step = step }
    }

    func next() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        go(next)
    }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        go(previous)
    }

    func done(_ gesture: Gesture) {
        guard step == .gestures, !gestures.contains(gesture) else { return }
        _ = withAnimation(.spring(duration: 0.45, bounce: 0.4)) { gestures.insert(gesture) }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    func contains(_ gesture: Gesture) -> Bool { gestures.contains(gesture) }

    func set(_ feature: Feature, on: Bool) {
        withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
            if on { features.insert(feature) } else { features.remove(feature) }
        }
    }

    /// Writes the choices to the settings: what the island shows, and its pages, Home first, then a page for each tool
    /// kept, in the order they matter.
    func save() {
        Preferences.showsMediaActivity = features.contains(.music)
        Preferences.showsLyrics = features.contains(.lyrics)
        Preferences.replacesSystemHUD = features.contains(.hud)
        Preferences.showsBattery = features.contains(.battery)
        Preferences.showsAudioDevices = features.contains(.headphones)
        Preferences.showsMicrophoneAndCamera = features.contains(.privacy)
        Preferences.showsAgents = features.contains(.agents)
        Preferences.keepsClipboardHistory = features.contains(.clipboard)
        Preferences.pageDeck = deck
    }
}

// MARK: The window

struct WelcomeView: View {
    let model: WelcomeModel
    let finish: () -> Void

    var body: some View {
        ZStack {
            GlowBackground()
            VStack(spacing: 0) {
                ZStack {
                    let direction = CGFloat(model.direction)
                    Group {
                        switch model.step {
                        case .discover: DiscoverStep(model: model)
                        case .island: IslandStep(model: model)
                        case .gestures: GesturesStep(model: model)
                        case .ready: ReadyStep()
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .offset(x: 70 * direction).combined(with: .opacity).combined(with: .blurred),
                        removal: .offset(x: -70 * direction).combined(with: .opacity).combined(with: .blurred)
                    ))
                    .id(model.step)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Footer(model: model, finish: finish)
            }
        }
        .frame(width: 640, height: 560)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
}

private struct Blur: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

private extension AnyTransition {
    static var blurred: AnyTransition { .modifier(active: Blur(radius: 14), identity: Blur(radius: 0)) }
}

/// Step dots and the buttons that move between steps.
private struct Footer: View {
    let model: WelcomeModel
    let finish: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 7) {
                ForEach(WelcomeModel.Step.allCases, id: \.rawValue) { step in
                    Capsule()
                        .fill(step == model.step ? Theme.accent : Color.white.opacity(0.2))
                        .frame(width: step == model.step ? 20 : 7, height: 7)
                }
            }
            .animation(.spring(duration: 0.4, bounce: 0.3), value: model.step)
            Spacer()
            if model.step != .discover {
                Button { model.back() } label: { Text("Back", bundle: .module) }
                    .buttonStyle(QuietButton())
            } else {
                // No title bar: Later, or Escape, closes the welcome; it comes back from the island's menu.
                Button { WelcomeWindow.shared.dismiss() } label: { Text("Later", bundle: .module) }
                    .buttonStyle(QuietButton())
                    .keyboardShortcut(.cancelAction)
            }
            Button {
                if model.step == .discover { model.save() }
                if model.step == .ready { finish() } else { model.next() }
            } label: {
                Text(model.step == .ready ? "Start using Col" : "Continue", bundle: .module)
            }
            .buttonStyle(AccentButton())
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 28)
    }
}

struct AccentButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 34)
            .background(
                Capsule().fill(Theme.accent.gradient)
                    .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 3)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.14 : 0.08)))
    }
}

/// A slow glow in the Mac's accent drifting behind the steps, animated by Core Animation so the window costs nothing
/// while idle.
private struct GlowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let glow = CAGradientLayer()
        glow.type = .radial
        let accent = NSColor(Theme.accent).usingColorSpace(.sRGB) ?? .systemBlue
        glow.colors = [accent.withAlphaComponent(0.28).cgColor, accent.withAlphaComponent(0).cgColor]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.frame = CGRect(x: -80, y: 260, width: 800, height: 520)
        let drift = CABasicAnimation(keyPath: "position.x")
        drift.fromValue = 280
        drift.toValue = 360
        drift.duration = 7
        drift.autoreverses = true
        drift.repeatCount = .infinity
        drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glow.add(drift, forKey: "drift")
        view.layer?.addSublayer(glow)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct StepHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: 8) {
            Text(title, bundle: .module)
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
            Text(subtitle, bundle: .module)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
    }
}

// MARK: Steps

private struct GesturesStep: View {
    let model: WelcomeModel

    var body: some View {
        VStack(spacing: 26) {
            StepHeader(title: "Try it on your notch", subtitle: "Do each gesture on the real notch, at the top of your screen. Each one ticks itself.")
            VStack(spacing: 10) {
                GestureRow(done: model.contains(.hover), symbol: "cursorarrow.rays", title: "Rest the pointer on the notch", detail: "It swells, then opens.")
                GestureRow(done: model.contains(.swipeDown), symbol: "hand.draw.fill", title: "Swipe down with two fingers", detail: "On the notch: it opens at once. Swipe up to close.")
                GestureRow(done: model.contains(.swipeSide), symbol: "arrow.left.and.right", title: "Swipe sideways on the open island", detail: "It moves between pages.")
            }
            .frame(width: 460)
        }
    }
}

private struct GestureRow: View {
    let done: Bool
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(done ? Color.green.opacity(0.18) : Color.white.opacity(0.07))
                Image(systemName: done ? "checkmark" : symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(done ? Color.green : .white.opacity(0.8))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 40, height: 40)
            .scaleEffect(done ? 1.08 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title, bundle: .module).font(.system(size: 14, weight: .semibold))
                Text(detail, bundle: .module).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(done ? 0.07 : 0.04))
                .strokeBorder(done ? Color.green.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct ReadyStep: View {
    @AppStorage("welcomeLaunchAtLogin") private var launchesAtLogin = true
    @AppStorage("welcomeChecksForUpdates") private var checksForUpdates = true
    @State private var shown = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.15)).frame(width: 110, height: 110).scaleEffect(shown ? 1 : 0.4)
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.bounce, value: shown)
            }
            StepHeader(title: "You’re all set", subtitle: "Look up: the island lives in your notch. Right-click it anytime for settings.")
            VStack(spacing: 0) {
                row("Open Col at login", isOn: $launchesAtLogin)
                Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 16)
                row("Keep Col up to date", isOn: $checksForUpdates)
            }
            .frame(width: 320)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
        }
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.45)) { shown = true }
        }
    }

    private func row(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title, bundle: .module).font(.system(size: 13))
            Spacer()
            Toggle(isOn: isOn) { Text(title, bundle: .module) }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
    }
}

// MARK: The greeting in the island

/// The island's first words. "Hello" in the Mac's own language, then in other languages and scripts, each word giving
/// way to the next in a soft blur, and back to the Mac's language with "Let's set up Col"; a click goes straight on.
/// After the welcome, it says "Let's go". Set in the system font: Col's own lettering, never Apple's handwriting.
struct GreetingView: View {
    let ready: Bool
    @State private var index = 0
    @State private var settled = false
    private let words = GreetingView.sequence(for: AppLanguage.current)

    /// "Hello" by language, written as each says it.
    static let hellos: [(language: String, word: String)] = [
        ("en", "Hello"), ("fr", "Bonjour"), ("es", "Hola"), ("de", "Hallo"), ("it", "Ciao"), ("pt", "Olá"),
        ("ja", "こんにちは"), ("zh", "你好"), ("ko", "안녕하세요"), ("ru", "Привет"), ("ar", "مرحبا"),
        ("hi", "नमस्ते"), ("el", "Γεια σου"), ("th", "สวัสดี"), ("he", "שלום"), ("tr", "Merhaba"),
        ("sv", "Hej"), ("pl", "Cześć"), ("vi", "Xin chào"), ("uk", "Привіт"),
    ]

    /// The Mac's language first and last; between them, seven others across scripts, never the same twice.
    static func sequence(for language: String) -> [String] {
        let code = String(language.prefix(2))
        let own = hellos.first { $0.language == code }?.word ?? "Hello"
        let order = ["en", "ja", "es", "ar", "zh", "fr", "hi", "it", "ko", "de", "ru", "pt", "el", "th"]
        let others = order.filter { $0 != code }.prefix(7).compactMap { language in hellos.first { $0.language == language }?.word }
        return [own] + others.filter { $0 != own } + [own]
    }

    private var still: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Text(verbatim: ready ? "" : words[index])
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.78)], startPoint: .top, endPoint: .bottom))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .id(index)
                    .transition(still ? AnyTransition.opacity : AnyTransition(.blurReplace))
                    .opacity(ready ? 0 : 1)
                if ready {
                    Text("Let’s go", bundle: .module)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.78)], startPoint: .top, endPoint: .bottom))
                        .transition(still ? AnyTransition.opacity : AnyTransition(.blurReplace))
                }
            }
            // Room for the blur and for scripts taller than Latin.
            .frame(height: 70)
            Group {
                if ready {
                    Text("Hover the notch whenever you need Col.", bundle: .module)
                } else {
                    Text("Let’s set up Col", bundle: .module)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(settled || ready ? 0.6 : 0))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { if !ready { IslandController.shared?.greetingDone() } }
        .task(id: ready) {
            guard !ready else { return }
            // Each word stays a little over a second; the fog between two takes most of a second.
            for next in 1..<words.count {
                try? await Task.sleep(for: .milliseconds(next == 1 ? 1500 : 1050))
                guard !Task.isCancelled else { return }
                withAnimation(still ? .easeInOut(duration: 0.4) : .smooth(duration: 0.85)) { index = next }
            }
            withAnimation(.easeOut(duration: 0.6)) { settled = true }
            try? await Task.sleep(for: .milliseconds(1700))
            guard !Task.isCancelled else { return }
            IslandController.shared?.greetingDone()
        }
    }
}
