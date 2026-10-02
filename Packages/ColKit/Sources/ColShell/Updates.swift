import Foundation

/// What the app's updater offers the settings and the island's menu. The app target provides it (Sparkle), so this
/// package stays free of the update framework.
@MainActor
public protocol UpdateChecking: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    /// A newer version a scheduled check found, waiting for the user.
    var pendingUpdateVersion: String? { get }
    func checkForUpdates()
}

@MainActor
public enum Updates {
    /// Set by the app at launch; nil in builds without an updater.
    public static weak var checker: UpdateChecking?
}
