import AppKit

/// Souffleur, the prompter's app before it joined Col. Running beside Col, it answers the same shortcuts and the same
/// phone as Col's prompter, and both roll a take at once. So Col asks it to quit when Col opens, as its own Quit command
/// would: never forced, so it can still save what it holds. The first time, the island says why. Souffleur's files, its
/// login item and the app itself are left as they are: whether it goes to the Trash is the user's choice. A development
/// build leaves it running.
@MainActor
enum Souffleur {
    nonisolated static let bundleIdentifier = "ch.rubencatalao.souffleur"
    /// "due" once Col has asked Souffleur to quit, "shown" once the island has said why.
    private static let noteKey = "souffleurNote"

    /// Asks each Souffleur running to quit. Returns true when one was.
    @discardableResult
    static func askToQuit() -> Bool {
        guard !AppLocation.isDevelopmentBuild else { return false }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).filter { !$0.isTerminated }
        guard !running.isEmpty else { return false }
        running.forEach { $0.terminate() }
        if UserDefaults.standard.string(forKey: noteKey) == nil { UserDefaults.standard.set("due", forKey: noteKey) }
        return true
    }

    /// Whether the island still has to say why Souffleur closed.
    static var noteIsDue: Bool { UserDefaults.standard.string(forKey: noteKey) == "due" }

    static func noteShown() {
        UserDefaults.standard.set("shown", forKey: noteKey)
    }
}
