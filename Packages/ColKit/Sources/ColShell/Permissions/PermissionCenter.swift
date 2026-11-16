import AppKit
import AVFoundation
import CoreBluetooth
import EventKit
import Observation
import Speech
import SwiftUI

/// Every permission Col can ask for, in one place: what it is for, which feature needs it, whether it is granted,
/// and how to ask. The welcome and the settings both read it, so they always say the same thing.
@MainActor
@Observable
final class PermissionCenter {
    static let shared = PermissionCenter()

    enum Permission: String, CaseIterable, Identifiable {
        case accessibility, calendars, bluetooth, camera, microphone, speech, audioCapture, location
        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            // macOS 27 renamed the pane that grants it.
            case .accessibility:
                ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
                    ? LocalizedStringResource("Device Control and Data Access", bundle: .settings)
                    : LocalizedStringResource("Accessibility", bundle: .settings)
            case .calendars: LocalizedStringResource("Calendars", bundle: .settings)
            case .bluetooth: LocalizedStringResource("Bluetooth", bundle: .settings)
            case .camera: LocalizedStringResource("Camera", bundle: .settings)
            case .microphone: LocalizedStringResource("Microphone", bundle: .settings)
            case .speech: LocalizedStringResource("Speech Recognition", bundle: .settings)
            case .audioCapture: LocalizedStringResource("System Audio Recording", bundle: .settings)
            case .location: LocalizedStringResource("Location", bundle: .settings)
            }
        }

        /// What Col does with it, and what happens without it.
        var detail: LocalizedStringResource {
            switch self {
            case .accessibility: LocalizedStringResource("Lets Col take over the volume and brightness keys, and keep its wings clear of the menus and icons of the menu bar. Without it, macOS shows its own display too, and the wings guess.", bundle: .settings)
            case .calendars: LocalizedStringResource("Shows your next events beside the clock. Without it, the agenda stays empty.", bundle: .settings)
            case .bluetooth: LocalizedStringResource("Reads the battery of your AirPods and other headphones. Without it, the card shows no battery.", bundle: .settings)
            case .camera: LocalizedStringResource("Used only while the mirror is open. Seeing that another app uses the camera needs no permission.", bundle: .settings)
            case .microphone: LocalizedStringResource("Lets the prompter roll while you speak and wait when you stop. The sound stays on your Mac and is never recorded.", bundle: .settings)
            case .speech: LocalizedStringResource("Lets Voice Follow keep your place word by word. Recognition runs on your Mac.", bundle: .settings)
            case .audioCapture: LocalizedStringResource("Lets the bars beside the camera follow the music itself. The sound is analysed on your Mac, never recorded or sent. Without it, the bars dance on their own.", bundle: .settings)
            case .location: LocalizedStringResource("Finds the weather where you are, to about a kilometre: only that rounded position goes to Open-Meteo. Without it, type a city in Settings.", bundle: .settings)
            }
        }

        /// The feature that needs it.
        var feature: LocalizedStringResource {
            switch self {
            case .accessibility: LocalizedStringResource("Volume and brightness", bundle: .settings)
            case .calendars: LocalizedStringResource("Agenda", bundle: .settings)
            case .bluetooth: LocalizedStringResource("AirPods and speakers", bundle: .settings)
            case .camera: LocalizedStringResource("Mirror", bundle: .settings)
            case .microphone, .speech: LocalizedStringResource("Prompter", bundle: .settings)
            case .audioCapture: LocalizedStringResource("Bars that follow the sound", bundle: .settings)
            case .location: LocalizedStringResource("Weather", bundle: .settings)
            }
        }

        var symbol: String {
            switch self {
            case .accessibility: "accessibility"
            case .calendars: "calendar"
            case .bluetooth: "airpodspro"
            case .camera: "camera.fill"
            case .microphone: "mic.fill"
            case .speech: "waveform"
            case .audioCapture: "speaker.wave.3.fill"
            case .location: "location.fill"
            }
        }

        var tint: Color {
            switch self {
            case .accessibility: .blue
            case .calendars: .red
            case .bluetooth: .blue
            case .camera: .gray
            case .microphone: .orange
            case .speech: .purple
            case .audioCapture: .pink
            case .location: .blue
            }
        }

        /// The page of Privacy & Security that lists it.
        fileprivate var anchor: String {
            switch self {
            case .accessibility: "Privacy_Accessibility"
            case .calendars: "Privacy_Calendars"
            case .bluetooth: "Privacy_Bluetooth"
            case .camera: "Privacy_Camera"
            case .microphone: "Privacy_Microphone"
            case .speech: "Privacy_SpeechRecognition"
            // System audio recording is listed with screen recording.
            case .audioCapture: "Privacy_ScreenCapture"
            case .location: "Privacy_LocationServices"
            }
        }
    }

    private(set) var accessibility = MediaKeyTap.isTrusted
    private(set) var calendars = EKEventStore.authorizationStatus(for: .event)
    private(set) var bluetooth = CBCentralManager.authorization
    private(set) var camera = AVCaptureDevice.authorizationStatus(for: .video)
    private(set) var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    private(set) var speech = SFSpeechRecognizer.authorizationStatus()
    private(set) var audioCapture = AudioCapturePermission.status
    /// Accessibility was asked for and the list in System Settings is open: say what to do there.
    private(set) var awaitingAccessibility = false

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        // macOS says when any app's Accessibility permission changes; the answer settles a moment later.
        observers.append(DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { MainActor.assumeIsolated { self?.refresh() } }
        })
    }

    func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility: accessibility
        case .calendars: calendars == .fullAccess
        case .bluetooth: bluetooth == .allowedAlways
        case .camera: camera == .authorized
        case .microphone: microphone == .authorized
        case .speech: speech == .authorized
        case .audioCapture: audioCapture == .granted
        case .location: LocationAccess.shared.isAllowed
        }
    }

    /// True when macOS will show its own prompt; false when only System Settings can change the answer.
    func canPrompt(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility: false
        case .calendars: calendars == .notDetermined
        case .bluetooth: bluetooth == .notDetermined
        case .camera: camera == .notDetermined
        case .microphone: microphone == .notDetermined
        case .speech: speech == .notDetermined
        case .audioCapture: audioCapture == .unknown
        case .location: LocationAccess.shared.canAsk
        }
    }

    func refresh() {
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
            accessibility = MediaKeyTap.isTrusted
            calendars = EKEventStore.authorizationStatus(for: .event)
            bluetooth = CBCentralManager.authorization
            camera = AVCaptureDevice.authorizationStatus(for: .video)
            microphone = AVCaptureDevice.authorizationStatus(for: .audio)
            speech = SFSpeechRecognizer.authorizationStatus()
            audioCapture = AudioCapturePermission.status
            if accessibility { awaitingAccessibility = false }
        }
    }

    /// Asks macOS, or opens the right page of System Settings when the user already answered.
    func request(_ permission: Permission) {
        guard canPrompt(permission) else {
            if permission == .accessibility {
                MediaKeyTap.requestTrust()
                awaitingAccessibility = true
            }
            openSettings(for: permission)
            return
        }
        switch permission {
        case .accessibility:
            break
        case .calendars:
            Task { @MainActor in
                _ = try? await EKEventStore().requestFullAccessToEvents()
                refresh()
            }
        case .bluetooth:
            // Reading a battery makes Core Bluetooth ask.
            _ = BluetoothAccessories.battery(forName: "")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MainActor.assumeIsolated { self.refresh() } }
        case .camera:
            Task { @MainActor in
                _ = await AVCaptureDevice.requestAccess(for: .video)
                refresh()
            }
        case .microphone:
            Task { @MainActor in
                _ = await AVCaptureDevice.requestAccess(for: .audio)
                refresh()
            }
        case .speech:
            Task { @MainActor in
                _ = await Self.requestSpeechRecognition()
                refresh()
            }
        case .audioCapture:
            // Without TCC's function, macOS asks the moment the bars first listen.
            let asked = AudioCapturePermission.request { @Sendable _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        PermissionCenter.shared.refresh()
                        SoundLevels.shared.permissionChanged()
                    }
                }
            }
            if !asked { SoundLevels.shared.listenOnce() }
        case .location:
            LocationAccess.shared.request()
        }
    }

    /// Speech answers on a queue of its own. Asked from here, outside the main actor, its answer is not taken for
    /// main-actor code: Swift 6 would stop the app the moment it arrived.
    private nonisolated static func requestSpeechRecognition() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in continuation.resume(returning: status) }
        }
    }

    func openSettings(for permission: Permission) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(permission.anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
