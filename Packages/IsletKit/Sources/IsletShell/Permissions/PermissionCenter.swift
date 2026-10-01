import AppKit
import AVFoundation
import CoreBluetooth
import EventKit
import Observation
import SwiftUI

/// Every permission Islet can ask for, in one place: what it is for, which feature needs it, whether it is granted,
/// and how to ask. The welcome and the settings both read it, so they always say the same thing.
@MainActor
@Observable
final class PermissionCenter {
    static let shared = PermissionCenter()

    enum Permission: String, CaseIterable, Identifiable {
        case accessibility, calendars, bluetooth, camera
        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .accessibility: LocalizedStringResource("Accessibility", bundle: .settings)
            case .calendars: LocalizedStringResource("Calendars", bundle: .settings)
            case .bluetooth: LocalizedStringResource("Bluetooth", bundle: .settings)
            case .camera: LocalizedStringResource("Camera", bundle: .settings)
            }
        }

        /// What Islet does with it, and what happens without it.
        var detail: LocalizedStringResource {
            switch self {
            case .accessibility: LocalizedStringResource("Lets Islet take over the volume and brightness keys. Without it, macOS shows its own display too.", bundle: .settings)
            case .calendars: LocalizedStringResource("Shows your next events beside the clock. Without it, the agenda stays empty.", bundle: .settings)
            case .bluetooth: LocalizedStringResource("Reads the battery of your AirPods and other headphones. Without it, the card shows no battery.", bundle: .settings)
            case .camera: LocalizedStringResource("Used only while the mirror is open. Seeing that another app uses the camera needs no permission.", bundle: .settings)
            }
        }

        /// The feature that needs it.
        var feature: LocalizedStringResource {
            switch self {
            case .accessibility: LocalizedStringResource("Volume and brightness", bundle: .settings)
            case .calendars: LocalizedStringResource("Agenda", bundle: .settings)
            case .bluetooth: LocalizedStringResource("AirPods and speakers", bundle: .settings)
            case .camera: LocalizedStringResource("Mirror", bundle: .settings)
            }
        }

        var symbol: String {
            switch self {
            case .accessibility: "accessibility"
            case .calendars: "calendar"
            case .bluetooth: "airpodspro"
            case .camera: "camera.fill"
            }
        }

        var tint: Color {
            switch self {
            case .accessibility: .blue
            case .calendars: .red
            case .bluetooth: .blue
            case .camera: .gray
            }
        }

        /// The page of Privacy & Security that lists it.
        fileprivate var anchor: String {
            switch self {
            case .accessibility: "Privacy_Accessibility"
            case .calendars: "Privacy_Calendars"
            case .bluetooth: "Privacy_Bluetooth"
            case .camera: "Privacy_Camera"
            }
        }
    }

    private(set) var accessibility = MediaKeyTap.isTrusted
    private(set) var calendars = EKEventStore.authorizationStatus(for: .event)
    private(set) var bluetooth = CBCentralManager.authorization
    private(set) var camera = AVCaptureDevice.authorizationStatus(for: .video)
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
        }
    }

    /// True when macOS will show its own prompt; false when only System Settings can change the answer.
    func canPrompt(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility: false
        case .calendars: calendars == .notDetermined
        case .bluetooth: bluetooth == .notDetermined
        case .camera: camera == .notDetermined
        }
    }

    func refresh() {
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
            accessibility = MediaKeyTap.isTrusted
            calendars = EKEventStore.authorizationStatus(for: .event)
            bluetooth = CBCentralManager.authorization
            camera = AVCaptureDevice.authorizationStatus(for: .video)
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
        }
    }

    func openSettings(for permission: Permission) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(permission.anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
