import AppKit
import ColCore

/// Turns what the Mac is doing into live activities: volume, brightness and the keyboard backlight, the sound output,
/// the battery, and the microphone and camera in use, or the microphone muted.
@MainActor
final class SystemActivities {
    let audio = AudioMonitor()
    let power = PowerMonitor()
    let camera = CameraMonitor()
    let keys = MediaKeyTap()
    let microphone = MicrophoneMute()

    var post: ((Activity) -> Void)?
    var remove: ((String) -> Void)?
    var registerImage: ((CGImage?, String) -> Void)?
    /// Bluetooth headphones just became the output.
    var onHeadphones: ((AudioMonitor.Output) -> Void)?

    private var microphoneApps: [NSRunningApplication] = []
    private var trustObserver: NSObjectProtocol?

    func start() {
        audio.onVolumeChange = { [weak self] level, muted in self?.showVolume(level, muted: muted) }
        audio.onOutputChange = { [weak self] output in self?.showOutput(output) }
        audio.onMicrophoneChange = { [weak self] apps in
            self?.microphoneApps = apps
            self?.microphone.users = apps.compactMap(\.localizedName)
            self?.refreshPrivacy()
        }
        microphone.onChange = { [weak self] _ in self?.refreshPrivacy() }
        camera.onChange = { [weak self] _ in self?.refreshPrivacy() }
        power.onChange = { [weak self] state, previous in self?.powerChanged(state, previous: previous) }
        keys.handler = { [weak self] press, fine in self?.handle(press, fine: fine) ?? false }

        audio.start()
        power.start()
        camera.start()
        // A mute Col could not undo before it stopped is undone now, whatever the setting.
        microphone.recover()
        if Preferences.mutesMicrophone { microphone.start() }
        startKeyTapIfAllowed()
        // Granting Accessibility in System Settings takes effect without a relaunch.
        trustObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated { self?.startKeyTapIfAllowed() }
            }
        }
    }

    func startKeyTapIfAllowed() {
        let wanted = Preferences.replacesSystemHUD || (Preferences.showsKeyboardBacklight && KeyboardBacklight.isAvailable)
        if wanted, MediaKeyTap.isTrusted { keys.start() } else { keys.stop() }
    }

    /// The microphone's mute was turned on or off in the settings: off, the microphone Col muted is unmuted.
    func microphoneSettingChanged() {
        if Preferences.mutesMicrophone { microphone.start() } else { microphone.stop() }
        refreshPrivacy()
    }

    // MARK: Volume and brightness

    private func showVolume(_ level: Double, muted: Bool) {
        let shown = muted ? 0 : level
        post?(Activity(
            id: "hud",
            priority: .transient,
            compact: CompactPresentation(
                leading: .symbol(SystemGlyphs.volume(level: level, muted: muted)),
                trailing: .level(shown)
            ),
            expires: Date().addingTimeInterval(1.6),
            updated: Date()
        ))
    }

    private func showBrightness(_ level: Double) {
        post?(Activity(
            id: "hud",
            priority: .transient,
            compact: CompactPresentation(
                leading: .symbol(SystemGlyphs.brightness(level: level), tint: .yellow),
                trailing: .level(level, tint: .yellow)
            ),
            expires: Date().addingTimeInterval(1.6),
            updated: Date()
        ))
    }

    private func showKeyboardBacklight(_ level: Double) {
        post?(Activity(
            id: "hud",
            priority: .transient,
            compact: CompactPresentation(
                leading: .symbol(SystemGlyphs.keyboardBacklight(level: level)),
                trailing: .level(level)
            ),
            expires: Date().addingTimeInterval(1.6),
            updated: Date()
        ))
    }

    /// Applies a volume, brightness or keyboard backlight key. Returns false to let macOS handle a key Col cannot.
    private func handle(_ press: MediaKeyPress, fine: Bool) -> Bool {
        if [.illuminationUp, .illuminationDown, .illuminationToggle].contains(press.key) {
            return handleBacklight(press, fine: fine)
        }
        // The tap may run for the keyboard backlight alone.
        guard Preferences.replacesSystemHUD else { return false }
        switch press.key {
        case .soundUp, .soundDown:
            guard audio.canSetVolume else { return false }
            guard press.isDown, let (level, muted) = audio.currentVolume() else { return true }
            let up = press.key == .soundUp
            let next = LevelStep.apply(to: muted && up ? 0 : level, up: up, fine: fine)
            audio.setVolume(next)
            audio.setMuted(next == 0)
            showVolume(next, muted: next == 0)
            return true
        case .mute:
            guard audio.canSetVolume else { return false }
            guard press.isDown, !press.isRepeat, let (level, muted) = audio.currentVolume() else { return true }
            audio.setMuted(!muted)
            showVolume(level, muted: !muted)
            return true
        case .brightnessUp, .brightnessDown:
            guard let level = Brightness.level else { return false }
            guard press.isDown else { return true }
            let next = LevelStep.apply(to: level, up: press.key == .brightnessUp, fine: fine)
            guard Brightness.set(next) else { return false }
            showBrightness(next)
            return true
        case .illuminationUp, .illuminationDown, .illuminationToggle:
            return false
        }
    }

    private func handleBacklight(_ press: MediaKeyPress, fine: Bool) -> Bool {
        guard Preferences.showsKeyboardBacklight, let level = KeyboardBacklight.level else { return false }
        guard press.isDown else { return true }
        if press.key == .illuminationToggle {
            guard !press.isRepeat else { return true }
            guard let next = KeyboardBacklight.toggle() else { return false }
            showKeyboardBacklight(next)
            return true
        }
        let next = LevelStep.apply(to: level, up: press.key == .illuminationUp, fine: fine)
        guard KeyboardBacklight.set(next) else { return false }
        showKeyboardBacklight(next)
        return true
    }

    // MARK: Sound output

    private func showOutput(_ output: AudioMonitor.Output) {
        guard Preferences.showsAudioDevices else { return }
        if output.transport == .bluetooth, Preferences.showsDeviceCard {
            onHeadphones?(output)
            return
        }
        post?(Activity(
            id: "audio.output",
            priority: .transient,
            compact: CompactPresentation(
                leading: .symbol(SystemGlyphs.audioDevice(name: output.name, transport: output.transport)),
                trailing: .text(SystemGlyphs.shortDeviceName(output.name))
            ),
            expires: Date().addingTimeInterval(3),
            updated: Date()
        ))
    }

    // MARK: Battery

    private func powerChanged(_ state: PowerMonitor.State, previous: PowerMonitor.State?) {
        guard Preferences.showsBattery, let previous else { return }
        let percent = state.level.formatted(.percent.precision(.fractionLength(0)))
        if state.onAdapter != previous.onAdapter {
            post?(Activity(
                id: "power",
                priority: .transient,
                compact: CompactPresentation(
                    leading: .text(percent, tint: state.onAdapter ? .green : .white),
                    trailing: .battery(level: state.level, charging: state.onAdapter)
                ),
                expires: Date().addingTimeInterval(3),
                updated: Date()
            ))
            return
        }
        // Warn once when crossing 20 % and 10 % on battery.
        let crossed = [0.2, 0.1].first { previous.level > $0 && state.level <= $0 }
        if !state.onAdapter, crossed != nil {
            post?(Activity(
                id: "power",
                priority: .alert,
                compact: CompactPresentation(leading: .text(percent, tint: .red), trailing: .battery(level: state.level, charging: false)),
                expires: Date().addingTimeInterval(5),
                updated: Date()
            ))
        }
    }

    // MARK: Microphone and camera

    /// When each app (or the camera) was last announced, and what the island last showed for them.
    private var privacyAnnounced: [String: Date] = [:]
    private var privacyShown: String?

    /// Says which app started listening or filming for a few seconds, then lets macOS's own indicator in the menu bar
    /// carry on, unless the user keeps it in the island. A muted microphone stays in sight as long as it is muted.
    private func refreshPrivacy() {
        let shows = Preferences.showsMicrophoneAndCamera
        let microphoneInUse = shows && !microphoneApps.isEmpty
        let cameraOn = shows && camera.inUse
        let muted = Preferences.mutesMicrophone && microphone.isMuted
        let app = microphoneInUse ? microphoneApps.first : nil
        registerImage?(app?.icon.flatMap(Self.bitmap(of:)), "privacy.app")
        guard let presentation = PrivacyIndicator.presentation(microphone: microphoneInUse, camera: cameraOn, muted: muted, appIcon: app != nil) else {
            remove?("privacy")
            privacyShown = nil
            return
        }
        let keeps = muted || Preferences.keepsPrivacyIndicator
        let users = (microphoneInUse ? microphoneApps.map { $0.bundleIdentifier ?? $0.localizedName ?? "app" } : [])
            + (cameraOn ? ["camera"] : [])
        let shown = "\(keeps)|\(muted)|" + users.sorted().joined(separator: ",")
        let now = Date()
        if keeps {
            privacyShown = shown
            post?(Activity(id: "privacy", priority: .standard, compact: presentation, updated: now))
            return
        }
        // Nothing new since the last announcement: it ran, or is still running.
        guard shown != privacyShown else { return }
        privacyShown = shown
        let fresh = PrivacyIndicator.fresh(users, announced: privacyAnnounced, now: now)
        guard !fresh.isEmpty else {
            remove?("privacy")
            return
        }
        for user in fresh { privacyAnnounced[user] = now }
        post?(Activity(id: "privacy", priority: .standard, compact: presentation,
                       expires: now.addingTimeInterval(PrivacyIndicator.announcement), updated: now))
    }

    /// Mutes or unmutes the microphone, from the island or the shortcut, and says so for a moment.
    func toggleMicrophone() {
        guard Preferences.mutesMicrophone, microphone.isAvailable else { return }
        microphone.toggle()
        let muted = microphone.isMuted
        post?(Activity(
            id: "hud",
            priority: .transient,
            compact: CompactPresentation(
                leading: .symbol(muted ? "mic.slash.fill" : "mic.fill", tint: muted ? .red : .white),
                trailing: .text(muted ? String(localized: "Muted", bundle: .module) : String(localized: "Microphone on", bundle: .module), tint: muted ? .red : .white)
            ),
            expires: Date().addingTimeInterval(1.6),
            updated: Date()
        ))
    }

    private static func bitmap(of image: NSImage) -> CGImage? {
        var rect = NSRect(x: 0, y: 0, width: 64, height: 64)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
