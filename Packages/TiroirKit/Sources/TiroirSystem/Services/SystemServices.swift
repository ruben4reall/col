import AppKit
import ServiceManagement
import TiroirCore

/// Tells when apps launch or quit, once per burst: an app often starts helpers along with it, and its icon appears
/// a moment after it launches.
@MainActor
public final class AppObserver {
    public var onChange: (@MainActor () -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    private let delay: Duration

    public init(delay: Duration = .milliseconds(900)) {
        self.delay = delay
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.changed() }
            })
        }
    }

    func changed() {
        pending?.cancel()
        pending = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }

    isolated deinit {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}

/// Tells when displays are added, removed or rearranged, and when the Mac wakes.
@MainActor
public final class DisplayObserver {
    public var onChange: (@MainActor () -> Void)?
    private var observers: [NSObjectProtocol] = []

    public init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.onChange?() } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.onChange?() } })
    }
}

public enum LoginItemStatus: Sendable, Equatable {
    case enabled
    case disabled
    /// Registered, waiting for the person to allow it in System Settings, General, Login Items & Extensions.
    case needsApproval
    case unavailable
}

/// Open at Login through SMAppService: macOS lists Tiroir in Login Items & Extensions, where it can also be removed.
@MainActor
public final class LoginItem {
    private let service: SMAppService

    public init(service: SMAppService = .mainApp) {
        self.service = service
    }

    public var status: LoginItemStatus {
        switch service.status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .needsApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled { try service.register() } else { try service.unregister() }
    }
}

/// Picks the engine for this Mac (spec 4.1).
@MainActor
public enum EngineFactory {
    public static func make(demo: Bool) -> MenuBarEngine {
        if demo { return DemoEngine() }
        let icons = AccessibilityIconSource()
        if PrivateAPI.hasMenuBarRestriction {
            return GoldenGateEngine(icons: icons)
        }
        return TahoeEngine(icons: icons, poster: SystemEventPoster())
    }
}

/// Memory footprint of this process, for Settings, General (the same measure as Activity Monitor's "Memory").
public enum MemoryUse {
    public static func footprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }
}
