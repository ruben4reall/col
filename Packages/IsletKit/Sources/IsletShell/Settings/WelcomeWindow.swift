import AppKit
import CoreBluetooth
import EventKit
import IsletCore
import Observation
import ServiceManagement
import SwiftUI

/// The first-launch welcome. The island greets first, from the notch; then this window teaches the gestures on the
/// real notch, lets the user pick modules, and asks only for the permissions those modules need.
@MainActor
final class WelcomeWindow: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindow()
    private var window: NSWindow?
    private(set) var model: WelcomeModel?
    private static let key = "hasWelcomed"

    static var hasWelcomed: Bool { UserDefaults.standard.bool(forKey: key) }

    func show() {
        if window == nil {
            let model = WelcomeModel()
            self.model = model
            let hosting = NSHostingController(rootView: WelcomeView(model: model) { [weak self] in self?.finish() })
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(srgbRed: 0.05, green: 0.05, blue: 0.055, alpha: 1)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 640, height: 560))
            window.center()
            // Sit a little below the centre, so the notch and the window read together.
            var frame = window.frame
            frame.origin.y -= 60
            window.setFrame(frame, display: false)
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
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
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: Self.key)
        window = nil
        model = nil
    }
}

@MainActor
@Observable
final class WelcomeModel {
    enum Step: Int, CaseIterable {
        case meet, gestures, modules, permissions, developers, ready
    }

    enum Gesture {
        case hover, swipeDown, swipeSide
    }

    enum Preset: String, CaseIterable, Identifiable {
        case essentials, developer, everything
        var id: String { rawValue }
    }

    var step: Step = .meet
    private(set) var direction = 1
    private(set) var gestures: Set<Gesture> = []
    var preset: Preset = .developer {
        didSet { apply(preset) }
    }
    var modules: Set<Module> = []

    enum Module: String, CaseIterable, Identifiable {
        case music, hud, battery, devices, privacy, shelf, clipboard, tools, system, agenda, agents
        var id: String { rawValue }
    }

    init() {
        apply(.developer)
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

    private func apply(_ preset: Preset) {
        switch preset {
        case .essentials: modules = [.music, .hud, .battery, .devices, .privacy, .shelf, .tools, .agenda]
        case .developer: modules = [.music, .hud, .battery, .devices, .privacy, .shelf, .clipboard, .tools, .system, .agenda, .agents]
        case .everything: modules = Set(Module.allCases)
        }
    }

    func toggle(_ module: Module) {
        if modules.contains(module) { modules.remove(module) } else { modules.insert(module) }
    }

    var needsAccessibility: Bool { modules.contains(.hud) }
    var needsBluetooth: Bool { modules.contains(.devices) }
    var needsCalendar: Bool { modules.contains(.agenda) }

    /// Writes the choices to the settings.
    func save() {
        Preferences.showsMediaActivity = modules.contains(.music)
        Preferences.replacesSystemHUD = modules.contains(.hud)
        Preferences.showsBattery = modules.contains(.battery)
        Preferences.showsAudioDevices = modules.contains(.devices)
        Preferences.showsMicrophoneAndCamera = modules.contains(.privacy)
        Preferences.showsAgents = modules.contains(.agents)
        Preferences.keepsClipboardHistory = modules.contains(.clipboard)
        let order: [(Module, String)] = [(.shelf, "shelf"), (.clipboard, "clipboard"), (.tools, "tools"), (.system, "system")]
        Preferences.enabledPages = order.filter { modules.contains($0.0) }.map(\.1)
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
                        case .meet: MeetStep(model: model)
                        case .gestures: GesturesStep(model: model)
                        case .modules: ModulesStep(model: model)
                        case .permissions: PermissionsStep(model: model)
                        case .developers: DevelopersStep()
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
        .tint(Theme.coral.color)
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
                        .fill(step == model.step ? Theme.coral.color : Color.white.opacity(0.2))
                        .frame(width: step == model.step ? 20 : 7, height: 7)
                }
            }
            .animation(.spring(duration: 0.4, bounce: 0.3), value: model.step)
            Spacer()
            if model.step != .meet {
                Button { model.back() } label: { Text("Back", bundle: .module) }
                    .buttonStyle(QuietButton())
            }
            Button {
                if model.step == .modules { model.save() }
                if model.step == .ready { finish() } else { model.next() }
            } label: {
                Text(model.step == .ready ? "Start using Islet" : (model.step == .meet ? "Get started" : "Continue"), bundle: .module)
            }
            .buttonStyle(CoralButton())
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 28)
    }
}

struct CoralButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 34)
            .background(
                Capsule().fill(LinearGradient(colors: [Color(red: 1, green: 0.55, blue: 0.42), Color(red: 0.89, green: 0.28, blue: 0.18)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color(red: 1, green: 0.42, blue: 0.27).opacity(0.5), radius: 12, y: 4)
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

/// A slow coral glow drifting behind the steps, animated by Core Animation so the window costs nothing while idle.
private struct GlowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let glow = CAGradientLayer()
        glow.type = .radial
        glow.colors = [NSColor(srgbRed: 1, green: 0.42, blue: 0.27, alpha: 0.32).cgColor, NSColor(srgbRed: 1, green: 0.42, blue: 0.27, alpha: 0).cgColor]
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

private struct StepHeader: View {
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

private struct MeetStep: View {
    let model: WelcomeModel
    @State private var shown = false

    var body: some View {
        VStack(spacing: 26) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .shadow(color: Color(red: 1, green: 0.42, blue: 0.27).opacity(0.45), radius: 30, y: 10)
                .scaleEffect(shown ? 1 : 0.6)
                .opacity(shown ? 1 : 0)
            StepHeader(title: "Welcome to Islet", subtitle: "The notch of your Mac becomes a living island: music, volume, battery, files, timers and your coding agents, right where you already look.")
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 14)
        }
        .padding(.top, 20)
        .onAppear {
            withAnimation(.spring(duration: 0.8, bounce: 0.35).delay(0.1)) { shown = true }
        }
    }
}

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

private struct ModulesStep: View {
    let model: WelcomeModel

    var body: some View {
        VStack(spacing: 18) {
            StepHeader(title: "Choose what the island shows", subtitle: "You can change all of this later in Settings.")
            Picker("", selection: Binding(get: { model.preset }, set: { model.preset = $0 })) {
                Text("Essentials", bundle: .module).tag(WelcomeModel.Preset.essentials)
                Text("Developer", bundle: .module).tag(WelcomeModel.Preset.developer)
                Text("Everything", bundle: .module).tag(WelcomeModel.Preset.everything)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 330)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(136), spacing: 10), count: 4), spacing: 10) {
                ForEach(WelcomeModel.Module.allCases) { module in
                    ModuleCard(module: module, on: model.modules.contains(module)) { model.toggle(module) }
                }
            }
        }
    }
}

private struct ModuleCard: View {
    let module: WelcomeModel.Module
    let on: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: module.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(on ? Theme.coral.color : .white.opacity(0.5))
                    Spacer()
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(on ? Theme.coral.color : .white.opacity(0.25))
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(module.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if module.needsPermission {
                    Label { Text("Permission", bundle: .module) } icon: { Image(systemName: "lock.fill") }
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            .padding(11)
            .frame(width: 136, height: 96, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(on ? 0.08 : 0.03))
                    .strokeBorder(on ? Theme.coral.color.opacity(0.45) : Color.white.opacity(0.06), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .animation(.spring(duration: 0.3, bounce: 0.3), value: on)
    }
}

extension WelcomeModel.Module {
    var symbol: String {
        switch self {
        case .music: "music.note"
        case .hud: "speaker.wave.2.fill"
        case .battery: "battery.100.bolt"
        case .devices: "airpodspro"
        case .privacy: "mic.fill"
        case .shelf: "tray.full.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .tools: "timer"
        case .system: "gauge.with.dots.needle.67percent"
        case .agenda: "calendar"
        case .agents: "sparkle"
        }
    }

    var title: LocalizedStringResource {
        let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)
        return switch self {
        case .music: LocalizedStringResource("Music", bundle: bundle)
        case .hud: LocalizedStringResource("Volume and brightness", bundle: bundle)
        case .battery: LocalizedStringResource("Battery", bundle: bundle)
        case .devices: LocalizedStringResource("AirPods and speakers", bundle: bundle)
        case .privacy: LocalizedStringResource("Microphone and camera", bundle: bundle)
        case .shelf: LocalizedStringResource("Shelf", bundle: bundle)
        case .clipboard: LocalizedStringResource("Clipboard", bundle: bundle)
        case .tools: LocalizedStringResource("Tools", bundle: bundle)
        case .system: LocalizedStringResource("System", bundle: bundle)
        case .agenda: LocalizedStringResource("Agenda", bundle: bundle)
        case .agents: LocalizedStringResource("Coding agents", bundle: bundle)
        }
    }

    var needsPermission: Bool { self == .hud || self == .agenda || self == .devices }
}

private struct PermissionsStep: View {
    let model: WelcomeModel
    @State private var trusted = MediaKeyTap.isTrusted
    @State private var calendar = EKEventStore.authorizationStatus(for: .event)
    @State private var bluetooth = CBCentralManager.authorization
    @State private var waiting = false

    var body: some View {
        VStack(spacing: 22) {
            StepHeader(title: "A couple of permissions", subtitle: "Only for the modules you chose. Everything else works without asking.")
            VStack(spacing: 10) {
                if model.needsAccessibility {
                    PermissionCard(symbol: "accessibility", tint: .blue, title: "Accessibility", detail: "So Islet can take over the volume and brightness keys.", granted: trusted) {
                        MediaKeyTap.requestTrust()
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        waiting = true
                    }
                }
                if model.needsCalendar {
                    PermissionCard(symbol: "calendar", tint: .red, title: "Calendars", detail: "So your next events show beside the clock.", granted: calendar == .fullAccess) {
                        Task { @MainActor in
                            _ = try? await EKEventStore().requestFullAccessToEvents()
                            withAnimation(.spring(duration: 0.4, bounce: 0.3)) { calendar = EKEventStore.authorizationStatus(for: .event) }
                        }
                    }
                }
                if model.needsBluetooth {
                    PermissionCard(symbol: "airpodspro", tint: .blue, title: "Bluetooth", detail: "So Islet can show the battery of your AirPods.", granted: bluetooth == .allowedAlways) {
                        _ = BluetoothAccessories.battery(forName: "")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MainActor.assumeIsolated { refresh() } }
                    }
                }
                if !model.needsAccessibility && !model.needsCalendar && !model.needsBluetooth {
                    Label { Text("Nothing to allow: your modules need no permission.", bundle: .module) } icon: { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
                        .font(.system(size: 14, weight: .medium))
                        .padding(.top, 20)
                }
            }
            .frame(width: 460)
            if waiting && !trusted {
                Text("Turn Islet on in the list that just opened, then come back here.", bundle: .module)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .transition(.opacity)
            }
            Text("Islet never asks for Screen Recording, Full Disk Access or Input Monitoring.", bundle: .module)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.35))
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onReceive(DistributedNotificationCenter.default().publisher(for: NSNotification.Name("com.apple.accessibility.api"))) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { MainActor.assumeIsolated { refresh() } }
        }
    }

    private func refresh() {
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
            trusted = MediaKeyTap.isTrusted
            calendar = EKEventStore.authorizationStatus(for: .event)
            bluetooth = CBCentralManager.authorization
        }
    }
}

private struct PermissionCard: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let granted: Bool
    var action: LocalizedStringKey = "Allow"
    let allow: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title, bundle: .module).font(.system(size: 14, weight: .semibold))
                Text(detail, bundle: .module).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button(action: allow) { Text(action, bundle: .module) }
                    .buttonStyle(CoralButton())
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}

private struct DevelopersStep: View {
    @State private var cliInstalled = FileManager.default.fileExists(atPath: CommandLineInstaller.linkURL.path)
    /// The AI agents set up on this Mac, found when the step appears.
    @State private var found: [CodingAgent] = CodingAgent.allCases.filter { CommandLineInstaller.isInstalled($0) }
    @State private var connected = false

    private var foundNames: String {
        ListFormatter.localizedString(byJoining: found.map(\.name))
    }

    var body: some View {
        VStack(spacing: 22) {
            StepHeader(title: "For developers", subtitle: "Optional. Scripts can show their progress in the notch, and your AI agents can ask for permission there.")
            VStack(spacing: 10) {
                PermissionCard(symbol: "terminal.fill", tint: .gray, title: "The islet command", detail: "Installs islet in ~/.local/bin.", granted: cliInstalled, action: "Install") {
                    _ = CommandLineInstaller.install()
                    withAnimation(.spring(duration: 0.4, bounce: 0.3)) { cliInstalled = FileManager.default.fileExists(atPath: CommandLineInstaller.linkURL.path) }
                }
                if found.isEmpty {
                    PermissionCard(symbol: "sparkle", tint: Color(red: 0.89, green: 0.28, blue: 0.18), title: "AI agents", detail: "Claude Code, Codex, Gemini CLI, Cursor and GitHub Copilot connect in Settings once installed.", granted: false, action: "Later") {}
                        .disabled(true)
                } else {
                    PermissionCard(symbol: "sparkle", tint: Color(red: 0.89, green: 0.28, blue: 0.18), title: "AI agents", detail: "Found on this Mac: \(foundNames). Adds Islet’s hooks to each, with a backup.", granted: connected, action: "Connect") {
                        for agent in found where !CommandLineInstaller.isConnected(agent) { _ = CommandLineInstaller.connect(agent) }
                        withAnimation(.spring(duration: 0.4, bounce: 0.3)) { connected = found.allSatisfy { CommandLineInstaller.isConnected($0) } }
                    }
                }
            }
            .frame(width: 460)
            .onAppear { connected = !found.isEmpty && found.allSatisfy { CommandLineInstaller.isConnected($0) } }
            Text("Islet never signs in to any AI service. It only hears the hooks your agents call on your Mac.", bundle: .module)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

private struct ReadyStep: View {
    @AppStorage("welcomeLaunchAtLogin") private var launchesAtLogin = true
    @AppStorage("welcomeChecksForUpdates") private var checksForUpdates = true
    @State private var shown = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill(Theme.coral.color.opacity(0.15)).frame(width: 110, height: 110).scaleEffect(shown ? 1 : 0.4)
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.coral.color)
                    .symbolEffect(.bounce, value: shown)
            }
            StepHeader(title: "You’re all set", subtitle: "Look up: the island lives in your notch. Right-click it anytime for settings.")
            VStack(spacing: 0) {
                row("Open Islet at login", isOn: $launchesAtLogin)
                Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 16)
                row("Keep Islet up to date", isOn: $checksForUpdates)
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

/// "Hello", written into the open island on first launch, before the welcome window appears.
struct GreetingView: View {
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 4) {
            Text("Hello", bundle: .module)
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.76), Color(red: 1, green: 0.48, blue: 0.35)], startPoint: .top, endPoint: .bottom))
                .mask(alignment: .leading) {
                    Rectangle().frame(width: revealed ? 400 : 0).frame(maxWidth: .infinity, alignment: .leading)
                }
                .blur(radius: revealed ? 0 : 6)
            Text("Let’s set up Islet", bundle: .module)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(revealed ? 0.6 : 0))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).delay(0.25)) { revealed = true }
        }
    }
}
