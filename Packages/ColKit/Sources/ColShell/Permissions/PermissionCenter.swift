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
        case accessibility, calendars, bluetooth, camera, microphone, speech
        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .accessibility: LocalizedStringResource("Accessibility", bundle: .settings)
            case .calendars: LocalizedStringResource("Calendars", bundle: .settings)
            case .bluetooth: LocalizedStringResource("Bluetooth", bundle: .settings)
            case .camera: LocalizedStringResource("Camera", bundle: .settings)
            case .microphone: LocalizedStringResource("Microphone", bundle: .settings)
            case .speech: LocalizedStringResource("Speech Recognition", bundle: .settings)
            }
        }

        /// What Col does with it, and what happens without it.
        var detail: LocalizedStringResource {
            switch self {
            case .accessibility: LocalizedStringResource("Lets Col take over the volume and brightness keys. Without it, macOS shows its own display too.", bundle: .settings)
            case .calendars: LocalizedStringResource("Shows your next events beside the clock. Without it, the agenda stays empty.", bundle: .settings)
            case .bluetooth: LocalizedStringResource("Reads the battery of your AirPods and other headphones. Without it, the card shows no battery.", bundle: .settings)
            case .camera: LocalizedStringResource("Used only while the mirror is open. Seeing that another app uses the camera needs no permission.", bundle: .settings)
            case .microphone: LocalizedStringResource("Lets the prompter roll while you speak and wait when you stop. The sound stays on your Mac and is never recorded.", bundle: .settings)
            case .speech: LocalizedStringResource("Lets Voice Follow keep your place word by word. Recognition runs on your Mac.", bundle: .settings)
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
            }
        }
    }

    private(set) var accessibility = MediaKeyTap.isTrusted
    private(set) var calendars = EKEventStore.authorizationStatus(for: .event)
    private(set) var bluetooth = CBCentralManager.authorization
    private(set) var camera = AVCaptureDevice.authorizationStatus(for: .video)
    private(set) var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    private(set) var speech = SFSpeechRecognizer.authorizationStatus()
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
