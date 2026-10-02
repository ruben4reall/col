import AppKit
import ColCore

/// Turns what the Mac is doing into live activities: volume and brightness, the sound output, the battery, and the
/// microphone and camera in use.
@MainActor
final class SystemActivities {
    let audio = AudioMonitor()
    let power = PowerMonitor()
    let camera = CameraMonitor()
    let keys = MediaKeyTap()

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
            self?.refreshPrivacy()
        }
        camera.onChange = { [weak self] _ in self?.refreshPrivacy() }
        power.onChange = { [weak self] state, previous in self?.powerChanged(state, previous: previous) }
        keys.handler = { [weak self] press, fine in self?.handle(press, fine: fine) ?? false }

        audio.start()
        power.start()
        camera.start()
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
        if Preferences.replacesSystemHUD, MediaKeyTap.isTrusted { keys.start() } else { keys.stop() }
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

    /// Applies a volume or brightness key. Returns false to let macOS handle a key Col cannot.
    private func handle(_ press: MediaKeyPress, fine: Bool) -> Bool {
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
        }
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

    private func refreshPrivacy() {
        guard Preferences.showsMicrophoneAndCamera else {
            remove?("privacy")
            return
        }
        let microphone = !microphoneApps.isEmpty
        let cameraOn = camera.inUse
        guard microphone || cameraOn else {
            remove?("privacy")
            return
        }
        let app = microphoneApps.first
        registerImage?(app?.icon.flatMap(Self.bitmap(of:)), "privacy.app")
        let leading: CompactItem = cameraOn ? .symbol("video.fill", tint: .green) : .symbol("mic.fill", tint: .orange)
        let trailing: CompactItem? = if cameraOn && microphone {
            .symbol("mic.fill", tint: .orange)
        } else if app != nil {
            .image(key: "privacy.app")
        } else {
            nil
        }
        post?(Activity(
            id: "privacy",
            priority: .standard,
            compact: CompactPresentation(leading: leading, trailing: trailing),
            updated: Date()
        ))
    }

    private static func bitmap(of image: NSImage) -> CGImage? {
        var rect = NSRect(x: 0, y: 0, width: 64, height: 64)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
