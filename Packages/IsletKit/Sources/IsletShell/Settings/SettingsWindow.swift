import AppKit
import CoreBluetooth
import EventKit
import AVFoundation
import IsletCore
import ServiceManagement
import SwiftUI

/// The settings window, laid out like System Settings. Islet has no Dock icon, so the window brings the app forward
/// while it is open, and is released when it closes: settings are rarely open.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    var extensions: ExtensionRunner?

    func show(_ pane: SettingsPane = .general) {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(extensions: extensions, initial: pane))
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Islet Settings", bundle: .module)
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.delegate = self
            // `-IsletSettingsHeight 900` opens it taller, for screenshots that show a whole pane.
            let height = UserDefaults.standard.double(forKey: "IsletSettingsHeight")
            window.setContentSize(NSSize(width: 780, height: height > 0 ? height : 580))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, island, activities, permissions, developers, about
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .island: "Island"
        case .activities: "Live activities"
        case .permissions: "Permissions"
        case .developers: "Developers"
        case .about: "About Islet"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .island: "capsule.fill"
        case .activities: "dot.radiowaves.left.and.right"
        case .permissions: "hand.raised.fill"
        case .developers: "chevron.left.forwardslash.chevron.right"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .island: Color(red: 0.93, green: 0.36, blue: 0.24)
        case .activities: .purple
        case .permissions: .blue
        case .developers: .indigo
        case .about: .gray
        }
    }
}

struct SettingsView: View {
    let extensions: ExtensionRunner?
    @State private var pane: SettingsPane

    init(extensions: ExtensionRunner?, initial: SettingsPane) {
        self.extensions = extensions
        _pane = State(initialValue: initial)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { item in
                Label {
                    Text(item.title, bundle: .module)
                } icon: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(item.tint.gradient))
                }
                .tag(item)
            }
            .navigationSplitViewColumnWidth(210)
        } detail: {
            Group {
                switch pane {
                case .general: GeneralPane()
                case .island: IslandPane()
                case .activities: ActivitiesPane()
                case .permissions: PermissionsPane()
                case .developers: DevelopersPane(extensions: extensions)
                case .about: AboutPane()
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text(pane.title, bundle: .module))
        }
        .frame(minWidth: 740, minHeight: 540)
    }
}

// MARK: General

private struct GeneralPane: View {
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var hotKey = Preferences.hotKeyEnabled
    @State private var fullScreen = Preferences.hidesInFullScreen
    @State private var display = Preferences.displayChoice
    @State private var keepsClipboard = Preferences.keepsClipboardHistory
    @State private var hidden = Preferences.hiddenFromScreenCapture

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $launchesAtLogin) { Text("Open Islet at login", bundle: .module) }
                    .onChange(of: launchesAtLogin) {
                        do {
                            if launchesAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchesAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            Section {
                Toggle(isOn: $hotKey) {
                    Text("Open the island with ⌃⌥⌘I", bundle: .module)
                    Text("A shortcut that works in every app.", bundle: .module)
                }
                .onChange(of: hotKey) { Preferences.hotKeyEnabled = hotKey }
                Toggle(isOn: $fullScreen) {
                    Text("Step aside in full screen", bundle: .module)
                    Text("Volume, alerts and requests still show.", bundle: .module)
                }
                .onChange(of: fullScreen) { Preferences.hidesInFullScreen = fullScreen }
                Picker(selection: $display) {
                    Text("The screen with the notch", bundle: .module).tag("notch")
                    Text("The screen you are working on", bundle: .module).tag("main")
                } label: { Text("Show the island on", bundle: .module) }
                .onChange(of: display) { Preferences.displayChoice = display }
            } header: {
                Text("Behaviour", bundle: .module)
            }
            Section {
                Toggle(isOn: $keepsClipboard) {
                    Text("Keep recent copies", bundle: .module)
                    Text("Kept in memory only, never written to disk. Copies from password managers are skipped.", bundle: .module)
                }
                .onChange(of: keepsClipboard) { Preferences.keepsClipboardHistory = keepsClipboard }
                Toggle(isOn: $hidden) {
                    Text("Hide the island from screenshots and recordings", bundle: .module)
                    Text("Useful when you share your screen.", bundle: .module)
                }
                .onChange(of: hidden) { Preferences.hiddenFromScreenCapture = hidden }
            } header: {
                Text("Privacy", bundle: .module)
            }
            Section {
                Button { WelcomeWindow.shared.show() } label: { Text("Show the Welcome Again…", bundle: .module) }
            }
        }
    }
}

// MARK: Island

private struct IslandPane: View {
    @State private var size = Preferences.islandSize
    @State private var motion = Preferences.motionStyle
    @State private var glass = Preferences.islandGlass
    @State private var opensOnHover = Preferences.opensOnHover
    @State private var delay = Preferences.hoverDelay
    @State private var enabled = Preferences.enabledPages

    var body: some View {
        Form {
            Section {
                IslandPreview(size: size, glass: IslandView.glassAvailable ? glass : .off, pages: [.home] + enabled.compactMap(IslandPage.init(key:)))
                    .frame(height: 170)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                Picker(selection: $size) {
                    Text("Compact", bundle: .module).tag(IslandSize.compact)
                    Text("Standard", bundle: .module).tag(IslandSize.standard)
                    Text("Large", bundle: .module).tag(IslandSize.large)
                } label: { Text("Size when open", bundle: .module) }
                .pickerStyle(.segmented)
                .onChange(of: size) { Preferences.islandSize = size }
                Picker(selection: $motion) {
                    Text("Snappy", bundle: .module).tag(MotionStyle.snappy)
                    Text("Standard", bundle: .module).tag(MotionStyle.standard)
                    Text("Relaxed", bundle: .module).tag(MotionStyle.relaxed)
                } label: { Text("Animation speed", bundle: .module) }
                .pickerStyle(.segmented)
                .onChange(of: motion) { Preferences.motionStyle = motion }
                if IslandView.glassAvailable {
                    Picker(selection: $glass) {
                        Text("Liquid", bundle: .module).tag(IslandGlass.liquid)
                        Text("Transparent", bundle: .module).tag(IslandGlass.transparent)
                        Text("Tinted", bundle: .module).tag(IslandGlass.tinted)
                        Text("Black", bundle: .module).tag(IslandGlass.off)
                    } label: { Text("Liquid Glass", bundle: .module) }
                    .pickerStyle(.segmented)
                    .onChange(of: glass) { Preferences.islandGlass = glass }
                }
            } header: {
                Text("Look and feel", bundle: .module)
            }
            Section {
                Toggle(isOn: $opensOnHover) { Text("Open when the pointer rests on the notch", bundle: .module) }
                    .onChange(of: opensOnHover) { Preferences.opensOnHover = opensOnHover }
                if opensOnHover {
                    LabeledContent {
                        HStack {
                            Slider(value: $delay, in: 0...0.8, step: 0.05)
                                .onChange(of: delay) { Preferences.hoverDelay = delay }
                            Text(Duration.milliseconds(Int(delay * 1000)), format: .units(allowed: [.milliseconds], width: .abbreviated))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 64, alignment: .trailing)
                        }
                    } label: {
                        Text("Delay before opening", bundle: .module)
                    }
                }
            } header: {
                Text("Opening", bundle: .module)
            } footer: {
                Text("A click or a two-finger swipe down always opens it at once.", bundle: .module)
            }
            Section {
                ForEach(IslandPage.optional) { page in
                    ModuleRow(page: page, isOn: enabled.contains(page.key), position: enabled.firstIndex(of: page.key), count: enabled.count) { on in
                        if on { enabled.append(page.key) } else { enabled.removeAll { $0 == page.key } }
                        Preferences.enabledPages = enabled
                    } move: { offset in
                        guard let index = enabled.firstIndex(of: page.key) else { return }
                        let target = min(max(index + offset, 0), enabled.count - 1)
                        enabled.move(fromOffsets: IndexSet(integer: index), toOffset: target > index ? target + 1 : target)
                        Preferences.enabledPages = enabled
                    }
                }
            } header: {
                Text("Pages", bundle: .module)
            } footer: {
                Text("Home and Live are always there. Turned-off pages leave the island entirely, tab included.", bundle: .module)
            }
        }
    }
}

private struct ModuleRow: View {
    let page: IslandPage
    let isOn: Bool
    let position: Int?
    let count: Int
    let toggle: (Bool) -> Void
    let move: (Int) -> Void
    @State private var hovering = false
    @State private var on = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: page.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(page.title)
                Text(page.summary).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if isOn, let position, hovering {
                HStack(spacing: 2) {
                    Button { move(-1) } label: { Image(systemName: "chevron.up") }
                        .disabled(position == 0)
                    Button { move(1) } label: { Image(systemName: "chevron.down") }
                        .disabled(position == count - 1)
                }
                .buttonStyle(.borderless)
                .transition(.opacity)
            }
            Toggle("", isOn: $on).labelsHidden().toggleStyle(.switch)
        }
        .onAppear { on = isOn }
        .onChange(of: on) { if on != isOn { toggle(on) } }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

extension IslandPage {
    var summary: LocalizedStringResource {
        let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)
        return switch self {
        case .home: LocalizedStringResource("Music, clock and agenda", bundle: bundle)
        case .shelf: LocalizedStringResource("Files dropped on the notch, AirDrop", bundle: bundle)
        case .clipboard: LocalizedStringResource("Your recent copies", bundle: bundle)
        case .tools: LocalizedStringResource("Timer, colour picker, mirror", bundle: bundle)
        case .system: LocalizedStringResource("Processor, memory, disk, network", bundle: bundle)
        case .live, .greeting, .device: LocalizedStringResource("Agents and activities from scripts", bundle: bundle)
        }
    }
}

/// The open island at the chosen size, with its tabs, on a wallpaper: what the settings will look like.
private struct IslandPreview: View {
    let size: IslandSize
    let glass: IslandGlass
    let pages: [IslandPage]

    var body: some View {
        GeometryReader { geometry in
            let notch = NotchMetrics(width: 188, height: 32, centerX: 0, isHardware: true)
            let layout = IslandLayout(notch: notch, size: size)
            let shape = layout.shape(for: .expanded)
            let scale = min(1, (geometry.size.height - 16) / shape.height, (geometry.size.width - 40) / shape.outerWidth)
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.36, green: 0.11, blue: 0.17), Color(red: 0.77, green: 0.27, blue: 0.18), Color(red: 1, green: 0.6, blue: 0.42)], startPoint: .top, endPoint: .bottom)
                ZStack(alignment: .top) {
                    switch glass {
                    case .liquid, .tinted: IslandLiquidGlass(shape: shape)
                    // The desktop seen through, dimmed as the island dims it.
                    case .transparent: IslandOutline(shape: shape).fill(.black.opacity(0.22)).frame(width: shape.outerWidth, height: shape.height)
                    case .off: EmptyView()
                    }
                    Path(IslandPath.make(shape, centerX: shape.outerWidth / 2))
                        .fill(glass == .off ? AnyShapeStyle(.black) : AnyShapeStyle(fade(layout, height: shape.height)))
                        .frame(width: shape.outerWidth, height: shape.height)
                    if glass == .transparent {
                        IslandOutline(shape: shape)
                            .stroke(.white.opacity(0.35), lineWidth: 2)
                            .mask(LinearGradient(stops: [.init(color: .clear, location: 0.55), .init(color: .white, location: 1)], startPoint: .top, endPoint: .bottom))
                            .clipShape(IslandOutline(shape: shape))
                            .frame(width: shape.outerWidth, height: shape.height)
                    }
                    HStack(spacing: 2) {
                        ForEach(pages) { page in
                            Image(systemName: page.symbol)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(page == .home ? .white : .white.opacity(0.36))
                                .frame(width: 24, height: 22)
                                .background(Capsule().fill(.white.opacity(page == .home ? 0.13 : 0)))
                        }
                        Spacer()
                        Color.clear.frame(width: notch.width + 12)
                        Spacer()
                        Image(systemName: "gearshape.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 16 + shape.earRadius)
                    .frame(width: shape.outerWidth, height: notch.height)
                    HStack(spacing: 16) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 1, green: 0.78, blue: 0.66), Color(red: 0.89, green: 0.28, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 80, height: 80)
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule().fill(.white).frame(width: 140, height: 10)
                            Capsule().fill(.white.opacity(0.45)).frame(width: 90, height: 8)
                            Capsule().fill(.white.opacity(0.15)).frame(height: 5).overlay(alignment: .leading) {
                                Capsule().fill(Theme.coral.color).frame(width: 110, height: 5)
                            }
                            .padding(.top, 10)
                        }
                    }
                    .padding(.horizontal, 22 + shape.earRadius)
                    .padding(.top, notch.height + 14)
                    .frame(width: shape.outerWidth, height: shape.height, alignment: .topLeading)
                }
                .frame(width: shape.outerWidth, height: shape.height)
                .scaleEffect(scale, anchor: .top)
                .animation(.spring(duration: 0.45, bounce: 0.2), value: size)
                .animation(.easeInOut(duration: 0.3), value: glass)
            }
        }
    }

    /// The same black the island draws over its glass.
    private func fade(_ layout: IslandLayout, height: CGFloat) -> LinearGradient {
        let stops = IslandView.fadeStops(for: layout, style: glass).map {
            Gradient.Stop(color: .black.opacity($0.alpha), location: min(max($0.y / height, 0), 1))
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }
}

/// Liquid Glass in the island's outline, as the open island has it under its black.
private struct IslandLiquidGlass: View {
    let shape: IslandShape

    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .frame(width: shape.width, height: shape.height)
                .glassEffect(.clear, in: .rect(cornerRadius: 28))
                .frame(width: shape.outerWidth, height: shape.height)
                .clipShape(IslandOutline(shape: shape))
        }
    }
}

private struct IslandOutline: Shape {
    let shape: IslandShape

    func path(in rect: CGRect) -> Path { Path(IslandPath.make(shape, centerX: rect.midX)) }
}

// MARK: Live activities

private struct ActivitiesPane: View {
    @State private var media = Preferences.showsMediaActivity
    @State private var tracks = Preferences.showsTrackChanges
    @State private var hud = Preferences.replacesSystemHUD
    @State private var devices = Preferences.showsAudioDevices
    @State private var battery = Preferences.showsBattery
    @State private var privacy = Preferences.showsMicrophoneAndCamera
    @State private var agents = Preferences.showsAgents
    @State private var lockScreen = Preferences.showsOnLockScreen
    @State private var deviceCard = Preferences.showsDeviceCard
    @State private var downloads = Preferences.watchesDownloads

    var body: some View {
        Form {
            Section {
                row("music.note", .pink, $media, "Music beside the camera", "The cover and the bars while something plays.") { Preferences.showsMediaActivity = $0 }
                row("text.badge.plus", .pink, $tracks, "Announce new tracks", "The title shows for a moment when a track starts.") { Preferences.showsTrackChanges = $0 }
            } header: { Text("Music", bundle: .module) }
            Section {
                row("speaker.wave.2.fill", .blue, $hud, "Replace the volume and brightness displays", "Needs Accessibility.") { Preferences.replacesSystemHUD = $0 }
                row("airpodspro", .gray, $devices, "Headphones and speakers", "The device the moment it connects.") { Preferences.showsAudioDevices = $0 }
                row("battery.75percent", .gray, $deviceCard, "Battery card for headphones", "Opens the island with the battery of each earbud and the case. Needs Bluetooth.") { Preferences.showsDeviceCard = $0 }
                row("battery.100.bolt", .green, $battery, "Charging and low battery", "When you plug in, and at 20 % and 10 %.") { Preferences.showsBattery = $0 }
                row("mic.fill", .orange, $privacy, "Microphone and camera in use", "Which app is listening or filming.") { Preferences.showsMicrophoneAndCamera = $0 }
            } header: { Text("System", bundle: .module) }
            Section {
                row("arrow.down.circle.fill", .blue, $downloads, "Downloads in progress", "Files your browser is still writing. Asks to read the Downloads folder.") { Preferences.watchesDownloads = $0 }
                row("sparkle", Color(red: 0.93, green: 0.36, blue: 0.24), $agents, "Coding agents", "Claude Code, Codex, Gemini CLI, Cursor and GitHub Copilot sessions, and the permission requests of Claude Code and Codex.") { Preferences.showsAgents = $0 }
                row("lock.fill", .indigo, $lockScreen, "Show on the Lock Screen", "Beta. Takes effect the next time Islet opens.") { Preferences.showsOnLockScreen = $0 }
            } header: { Text("More", bundle: .module) }
        }
    }

    private func row(_ symbol: String, _ tint: Color, _ value: Binding<Bool>, _ title: LocalizedStringKey, _ detail: LocalizedStringKey, save: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: value) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.gradient))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title, bundle: .module)
                    Text(detail, bundle: .module).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: value.wrappedValue) { save(value.wrappedValue) }
    }
}

// MARK: Permissions

private struct PermissionsPane: View {
    @State private var trusted = MediaKeyTap.isTrusted
    @State private var calendar = EKEventStore.authorizationStatus(for: .event)
    @State private var camera = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var bluetooth = CBCentralManager.authorization

    var body: some View {
        Form {
            Section {
                PermissionRow(symbol: "accessibility", tint: .blue, title: "Accessibility",
                              detail: "Lets Islet take over the volume and brightness keys. Without it, macOS shows its own display too.",
                              granted: trusted) {
                    MediaKeyTap.requestTrust()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                PermissionRow(symbol: "calendar", tint: .red, title: "Calendars",
                              detail: "Shows your next events beside the clock. Without it, the agenda stays empty.",
                              granted: calendar == .fullAccess) {
                    if calendar == .notDetermined {
                        Task { @MainActor in
                            _ = try? await EKEventStore().requestFullAccessToEvents()
                            calendar = EKEventStore.authorizationStatus(for: .event)
                        }
                    } else {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    }
                }
                PermissionRow(symbol: "airpodspro", tint: .blue, title: "Bluetooth",
                              detail: "Reads the battery of your AirPods and other headphones. Without it, the card shows no battery.",
                              granted: bluetooth == .allowedAlways) {
                    if bluetooth == .notDetermined {
                        _ = BluetoothAccessories.battery(forName: "")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MainActor.assumeIsolated { bluetooth = CBCentralManager.authorization } }
                    } else {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!)
                    }
                }
                PermissionRow(symbol: "camera.fill", tint: .gray, title: "Camera",
                              detail: "Used only while the mirror is open. Seeing that another app uses the camera needs no permission.",
                              granted: camera == .authorized) {
                    if camera == .notDetermined {
                        Task { @MainActor in
                            _ = await AVCaptureDevice.requestAccess(for: .video)
                            camera = AVCaptureDevice.authorizationStatus(for: .video)
                        }
                    } else {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                    }
                }
            } footer: {
                Text("Islet never asks for Screen Recording, Full Disk Access or Input Monitoring. It sees that the microphone is in use without ever listening to it.", bundle: .module)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trusted = MediaKeyTap.isTrusted
            calendar = EKEventStore.authorizationStatus(for: .event)
            camera = AVCaptureDevice.authorizationStatus(for: .video)
            bluetooth = CBCentralManager.authorization
        }
    }
}

private struct PermissionRow: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let granted: Bool
    let grant: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title, bundle: .module)
                Text(detail, bundle: .module).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if granted {
                Label { Text("Allowed", bundle: .module) } icon: { Image(systemName: "checkmark.circle.fill") }
                    .foregroundStyle(.green)
                    .font(.callout.weight(.medium))
            } else {
                Button(action: grant) { Text("Allow…", bundle: .module) }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: Developers

private struct DevelopersPane: View {
    let extensions: ExtensionRunner?
    @State private var cliMessage: String?
    @State private var cliInstalled = FileManager.default.fileExists(atPath: CommandLineInstaller.linkURL.path)

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    if cliInstalled {
                        Label { Text("Installed", bundle: .module) } icon: { Image(systemName: "checkmark.circle.fill") }.foregroundStyle(.green)
                    } else {
                        Button {
                            cliMessage = CommandLineInstaller.install()
                            cliInstalled = FileManager.default.fileExists(atPath: CommandLineInstaller.linkURL.path)
                        } label: { Text("Install", bundle: .module) }
                    }
                } label: {
                    Text("The islet command", bundle: .module)
                    Text(cliMessage ?? String(localized: "Push live activities from any script: islet push build --progress 40%", bundle: .module))
                }
            } header: {
                Text("Programmable notch", bundle: .module)
            }
            Section {
                ForEach(CodingAgent.allCases, id: \.self) { agent in
                    AgentConnectionRow(agent: agent)
                }
            } header: {
                Text("AI agents", bundle: .module)
            } footer: {
                Text("Islet never signs in to any AI service: it only hears the hooks each agent calls on your Mac. VS Code keeps Copilot permissions according to each session's mode. ChatGPT for macOS has no activity hooks; other agents and scripts can report with islet agent.", bundle: .module)
            }
            if let extensions {
                Section {
                    if extensions.installed.isEmpty {
                        Text("Put an extension folder here, with an extension.json and a script. Each one shows what its script prints.", bundle: .module)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(extensions.installed) { item in
                        Toggle(isOn: Binding(get: { item.enabled }, set: { extensions.setEnabled($0, folder: item.folder) })) {
                            Text(item.manifest.name)
                            Text(item.lastError ?? item.manifest.description ?? item.manifest.command)
                                .foregroundStyle(item.lastError == nil ? Color.secondary : Color.orange)
                        }
                    }
                    HStack {
                        Button { extensions.revealFolder() } label: { Text("Open the Extensions Folder", bundle: .module) }
                        Button { extensions.reload() } label: { Text("Reload", bundle: .module) }
                    }
                } header: {
                    Text("Extensions", bundle: .module)
                }
            }
            Section {
                Link(destination: URL(string: "https://github.com/ruben4reall/islet/blob/main/docs/api.md")!) { Text("API reference", bundle: .module) }
                Link(destination: URL(string: "https://github.com/ruben4reall/islet/blob/main/docs/extensions.md")!) { Text("Writing an extension", bundle: .module) }
            }
        }
    }
}

/// One coding agent: whether it is on this Mac, whether it reports to Islet, and the button to change that.
private struct AgentConnectionRow: View {
    let agent: CodingAgent
    @State private var connected = false
    @State private var installed = true
    @State private var message: String?

    var body: some View {
        LabeledContent {
            if installed || connected {
                Button {
                    message = connected ? CommandLineInstaller.disconnect(agent) : CommandLineInstaller.connect(agent)
                    connected = CommandLineInstaller.isConnected(agent)
                } label: { Text(connected ? "Disconnect" : "Connect", bundle: .module) }
            } else {
                Text("Not on this Mac", bundle: .module).foregroundStyle(.tertiary)
            }
        } label: {
            HStack(spacing: 6) {
                Text(agent.name)
                if connected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).imageScale(.small) }
            }
            Text(message ?? (agent.answersPermissions
                ? String(localized: "Sessions in the notch, and permission requests with Allow and Deny.", bundle: .module)
                : String(localized: "Sessions in the notch; you answer permission requests in the agent.", bundle: .module)))
        }
        .onAppear {
            connected = CommandLineInstaller.isConnected(agent)
            installed = CommandLineInstaller.isInstalled(agent)
        }
    }
}

// MARK: About

private struct AboutPane: View {
    @State private var automatic = Updates.checker?.automaticallyChecksForUpdates ?? false

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                    Text("Islet").font(.system(size: 26, weight: .bold))
                    Text("The notch, made useful.", bundle: .module).foregroundStyle(.secondary)
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")", bundle: .module)
                        .font(.callout).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            if let checker = Updates.checker {
                Section {
                    if let pending = checker.pendingUpdateVersion {
                        LabeledContent {
                            Button { checker.checkForUpdates() } label: { Text("Install…", bundle: .module) }
                        } label: {
                            Text("Islet \(pending) is available", bundle: .module)
                        }
                    }
                    Toggle(isOn: $automatic) { Text("Check for updates automatically", bundle: .module) }
                        .onChange(of: automatic) { checker.automaticallyChecksForUpdates = automatic }
                    Button { checker.checkForUpdates() } label: { Text("Check for Updates…", bundle: .module) }
                        .disabled(!checker.canCheckForUpdates)
                } header: {
                    Text("Updates", bundle: .module)
                } footer: {
                    Text("Updates are signed and come from the Islet website. Islet makes no other network request.", bundle: .module)
                }
            }
            Section {
                Link(destination: URL(string: "https://getislet.vercel.app")!) { Text("Website", bundle: .module) }
                Link(destination: URL(string: "https://github.com/ruben4reall/islet")!) { Text("Source code on GitHub", bundle: .module) }
                Link(destination: URL(string: "https://github.com/ruben4reall/islet/issues")!) { Text("Report a problem", bundle: .module) }
                Button { WelcomeWindow.shared.show() } label: { Text("Show the Welcome Again…", bundle: .module) }
            }
            Section {
                Button(role: .destructive) { NSApp.terminate(nil) } label: { Text("Quit Islet", bundle: .module) }
            } footer: {
                Text("MIT License. Islet is not affiliated with Apple.", bundle: .module)
            }
        }
    }
}
