import AppKit

/// Souffleur, the prompter's app before it joined Col. Running beside Col, it answers the same shortcuts and the same
/// phone as Col's prompter, and both roll a take at once. So Col asks it to quit when Col opens, as its own Quit command
/// would: never forced, so it can still save what it holds, or stay open. The first time it quits, the island says
/// why. Souffleur's files, its login item and the app itself are left as they are: whether it goes to the Trash is the
/// user's choice. A development build leaves it running.
@MainActor
enum Souffleur {
    nonisolated static let bundleIdentifier = "ch.rubencatalao.souffleur"
    /// "due" once a Souffleur Col asked to quit has quit, "shown" once the island has said why.
    private static let noteKey = "souffleurNote"

    /// Asks each Souffleur running to quit, and returns those the request reached. One still launching is not reached;
    /// one reached can still stay open, a sheet left open for instance: only `didQuit()` makes the note due.
    static func askToQuit() -> [NSRunningApplication] {
        guard !AppLocation.isDevelopmentBuild else { return [] }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).filter { !$0.isTerminated && $0.terminate() }
    }

    /// A Souffleur Col asked to quit has quit: the island has to say why, unless it already did.
    static func didQuit() {
        if UserDefaults.standard.string(forKey: noteKey) == nil { UserDefaults.standard.set("due", forKey: noteKey) }
    }

    /// Whether the island still has to say why Souffleur closed.
    static var noteIsDue: Bool { UserDefaults.standard.string(forKey: noteKey) == "due" }

    static func noteShown() {
        UserDefaults.standard.set("shown", forKey: noteKey)
    }
}
