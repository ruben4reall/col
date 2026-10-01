import AppKit

/// Offers, once, to move Islet into Applications when it was opened from somewhere else, such as the disk image or
/// Downloads: login items and updates need it to stay in one place.
@MainActor
enum ApplicationsFolder {
    private static let declinedKey = "declinedMoveToApplications"

    /// Returns true when the app is being moved and relaunched, so launching should stop here.
    static func offerToMoveIfNeeded() -> Bool {
        let bundle = Bundle.main.bundleURL
        let path = bundle.path
        let applications = ["/Applications/", NSHomeDirectory() + "/Applications/"]
        // Development builds live in build folders: never offer to move those.
        guard !applications.contains(where: path.hasPrefix), !path.contains("/.build/"), !path.contains("/DerivedData/"),
              !UserDefaults.standard.bool(forKey: declinedKey)
        else { return false }

        let alert = NSAlert()
        alert.messageText = String(localized: "Move Islet to the Applications folder?")
        alert.informativeText = String(localized: "Islet works best from Applications: it can open at login and update itself there.")
        alert.addButton(withTitle: String(localized: "Move to Applications"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        alert.icon = NSApp.applicationIconImage
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else {
            UserDefaults.standard.set(true, forKey: declinedKey)
            return false
        }
        let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(bundle.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.trashItem(at: destination, resultingItemURL: nil)
            }
            try FileManager.default.copyItem(at: bundle, to: destination)
        } catch {
            let failure = NSAlert(error: error)
            failure.runModal()
            return false
        }
        // Open the copy once this process has exited, then quit; the disk image can then be ejected.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The moved Islet starts once this one is gone.
        relaunch.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open \"$0\"",
                              destination.path, String(ProcessInfo.processInfo.processIdentifier)]
        try? relaunch.run()
        NSApp.terminate(nil)
        return true
    }
}
