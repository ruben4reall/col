import AppKit
import ApplicationServices

/// The one permission Tiroir needs (spec 6.1): Accessibility, to see which app owns each icon, to open icons and, on
/// macOS 26, to move them. Tiroir never asks for Screen Recording.
@MainActor
public final class AccessibilityPermission {
    public private(set) var isTrusted: Bool
    /// Called on the main actor when the grant changes, whichever way.
    public var onChange: (@MainActor (Bool) -> Void)?

    private var observer: NSObjectProtocol?
    private var pollTimer: Timer?

    public init() {
        isTrusted = AXIsProcessTrusted()
        // System Settings posts this distributed notification when any app's Accessibility grant changes. The new
        // value is readable a moment later.
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                self?.refresh()
            }
        }
    }

    public func refresh() {
        let trusted = AXIsProcessTrusted()
        guard trusted != isTrusted else { return }
        isTrusted = trusted
        if trusted { stopWaiting() }
        onChange?(trusted)
    }

    /// Shows the system's Accessibility prompt once, which also adds Tiroir to the list in System Settings.
    public func request() {
        // The value of kAXTrustedCheckOptionPrompt, spelled out: the global is not concurrency-safe in Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings at Privacy & Security, Accessibility.
    public func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// While the welcome or Settings waits for the grant, checks once a second as well: the distributed notification
    /// does not always arrive when an app is added with the plus button. Stops by itself once granted.
    public func waitForGrant() {
        guard !isTrusted, pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    public func stopWaiting() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
