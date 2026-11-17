import AppKit
import TiroirCore

/// Tells when apps launch or quit, once per burst: an app often starts helpers along with it, and its icon appears
/// a moment after it launches.
@available(macOS 26, *)
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

    public func stop() {
        pending?.cancel()
        pending = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }

    isolated deinit {
        stop()
    }
}

/// Tells when displays are added, removed or rearranged, and when the Mac wakes.
@available(macOS 26, *)
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

    public func stop() {
        guard observers.count == 2 else { return }
        NotificationCenter.default.removeObserver(observers[0])
        NSWorkspace.shared.notificationCenter.removeObserver(observers[1])
        observers.removeAll()
    }

    isolated deinit {
        stop()
    }
}

/// Picks the engine for this Mac (spec 4.1).
@available(macOS 26, *)
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
