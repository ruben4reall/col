import AppKit
import ColShell

/// Offers to move Col into Applications when it was opened from somewhere else, such as the disk image or Downloads:
/// login items and updates need it to stay in one place.
@MainActor
enum ApplicationsFolder {
    private static let declinedKey = "declinedMoveToApplications"

    /// Returns true when the app is being moved and relaunched, so launching should stop here. The relaunched app opens
    /// `urls`, what this launch was asked to open.
    static func offerToMoveIfNeeded(opening urls: [URL] = []) -> Bool {
        // Development builds live in build folders: never offer to move those.
        guard !AppLocation.isDevelopmentBuild else { return false }
        // Where the user put the app: macOS may run a translocated copy of it.
        let bundle = AppLocation.bundleURL
        if AppLocation.isInApplications(bundle) {
            return AppLocation.isTranslocated && release(bundle, opening: urls)
        }
        // From its disk image or translocated, the app is only passing through: it asks at each launch, and a Not Now
        // given there, or once under Islet, is not kept.
        let passing = !AppLocation.isStable
        guard passing || !UserDefaults.standard.bool(forKey: declinedKey) else { return false }

        let alert = NSAlert()
        alert.messageText = String(localized: "Move Col to the Applications folder?")
        alert.informativeText = String(localized: "Col works best from Applications: it can open at login and update itself there.")
        alert.addButton(withTitle: String(localized: "Move to Applications"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        alert.icon = NSApp.applicationIconImage
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else {
            if !passing { UserDefaults.standard.set(true, forKey: declinedKey) }
            return false
        }
        return moveNow(opening: urls)
    }

    /// Copies Col to Applications (a copy already there goes to the Trash), then quits and opens the copy. Returns false
    /// when nothing moved: a development build, which never replaces the installed Col; a copy that is already where it
    /// would go; or a copy that failed, which the user is told. The menu bar's drawers ask for it on macOS 27, which
    /// honours only apps in the Mac's own Applications folder: with `sharedFolderOnly`, the folder in the user's home
    /// will not do, and the user is told when the Mac's cannot be written.
    @discardableResult
    static func moveNow(opening urls: [URL] = [], sharedFolderOnly: Bool = false) -> Bool {
        guard !AppLocation.isDevelopmentBuild else { return false }
        let bundle = AppLocation.bundleURL
        let files = FileManager.default
        let sharedIsWritable = files.isWritableFile(atPath: "/Applications")
        guard let destination = AppLocation.moveDestination(for: bundle, sharedIsWritable: sharedIsWritable,
                                                            allowsHome: !sharedFolderOnly) else {
            if !sharedIsWritable, sharedFolderOnly {
                let alert = NSAlert()
                alert.messageText = String(localized: "Col cannot move itself into the Applications folder")
                alert.informativeText = String(localized: "Your account cannot write there. Ask the person who manages this Mac to move Col into Applications.")
                NSApp.activate()
                alert.runModal()
            }
            return false
        }
        do {
            try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if files.fileExists(atPath: destination.path) {
                try files.trashItem(at: destination, resultingItemURL: nil)
            }
            try files.copyItem(at: bundle, to: destination)
        } catch {
            let failure = NSAlert(error: error)
            failure.runModal()
            return false
        }
        // The copy keeps the disk image's quarantine, and macOS would run it translocated, away from Applications.
        AppLocation.removeQuarantine(from: destination)
        // Opens the copy once this process has exited; the disk image can then be ejected.
        AppLocation.relaunch(at: destination, opening: urls)
        return true
    }

    /// An app put in Applications by something other than the Finder kept its quarantine, so macOS runs it translocated:
    /// it could neither open at login nor update itself. Freed of it, it opens again from where it is. Returns true when
    /// it does; an app already free of it that still runs translocated is left as it is, so this never loops.
    private static func release(_ bundle: URL, opening urls: [URL]) -> Bool {
        guard AppLocation.isQuarantined(bundle), AppLocation.removeQuarantine(from: bundle) else { return false }
        AppLocation.relaunch(at: bundle, opening: urls)
        return true
    }
}
