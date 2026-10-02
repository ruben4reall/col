import AppKit
import ServiceManagement

/// Islet became Col with 2.0. On the first launch under the new name, everything takes it without the user noticing:
/// the app on disk, the folders it keeps, the command and the login item. Whatever was set up under Islet keeps
/// working: its links, its hooks, its scripts.
@MainActor
public enum NameChange {
    private static let legacy = "Islet"
    private static let doneKey = "nameChangeDone"

    /// Development builds leave the user's own files alone, unless `-ColMigrate YES` asks, run under a home of its own
    /// (CFFIXED_USER_HOME); then nothing is remembered, so the real move still happens later.
    private static var forced: Bool { UserDefaults.standard.bool(forKey: "ColMigrate") }

    private static var isDevelopmentBuild: Bool { AppLocation.isDevelopmentBuild }

    /// Sparkle installs an update where the app was, under its old file name: Islet.app takes its new name, Col.app,
    /// and starts again from there. Returns true when it does, so launching stops here.
    public static func renameBundleIfNeeded() -> Bool {
        let bundle = Bundle.main.bundleURL
        guard bundle.deletingPathExtension().lastPathComponent == legacy, !isDevelopmentBuild || forced else { return false }
        let renamed = bundle.deletingLastPathComponent().appendingPathComponent("Col.app")
        guard !FileManager.default.fileExists(atPath: renamed.path),
              (try? FileManager.default.moveItem(at: bundle, to: renamed)) != nil
        else { return false }
        AppLocation.relaunch(at: renamed)
        return true
    }

    /// Moves what Islet kept to Col's folders, once. Runs before anything reads them.
    public static func migrateIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: doneKey) || forced, !isDevelopmentBuild || forced else { return }
        let files = FileManager.default
        for directory in [FileManager.SearchPathDirectory.applicationSupportDirectory, .cachesDirectory] {
            let base = files.urls(for: directory, in: .userDomainMask)[0]
            move(base.appendingPathComponent(legacy, isDirectory: true), into: base.appendingPathComponent("Col", isDirectory: true))
        }
        // The socket Islet left, now in Col's folder: nothing answers on it.
        let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Col")
        try? files.removeItem(at: support.appendingPathComponent("islet.sock"))

        let defaults = UserDefaults.standard
        let frame = "NSWindow Frame ColFloatingPrompter"
        if defaults.object(forKey: frame) == nil, let old = defaults.object(forKey: "NSWindow Frame IsletFloatingPrompter") {
            defaults.set(old, forKey: frame)
        }
        relinkCommand()
        trashOlderCopies()
        // The login item was registered for Islet.app.
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
            try? SMAppService.mainApp.register()
        }
        if !forced { defaults.set(true, forKey: doneKey) }
    }

    /// Moves a folder to its new place. When both exist, what the old one holds joins the new one, folder by folder;
    /// nothing already there is replaced.
    nonisolated static func move(_ old: URL, into new: URL) {
        let files = FileManager.default
        var isFolder: ObjCBool = false
        guard files.fileExists(atPath: old.path) else { return }
        guard files.fileExists(atPath: new.path, isDirectory: &isFolder) else {
            try? files.moveItem(at: old, to: new)
            return
        }
        guard isFolder.boolValue else { return }
        for item in (try? files.contentsOfDirectory(at: old, includingPropertiesForKeys: nil)) ?? [] {
            move(item, into: new.appendingPathComponent(item.lastPathComponent))
        }
    }

    /// Hooks installed under Islet call ~/.local/bin/islet: that link now leads to `colctl`, which sits beside it.
    private static func relinkCommand() {
        let files = FileManager.default
        let bin = files.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")
        let old = bin.appendingPathComponent("islet")
        guard (try? files.destinationOfSymbolicLink(atPath: old.path)) != nil, let tool = CommandLineInstaller.bundledTool else { return }
        try? files.removeItem(at: old)
        try? files.createSymbolicLink(at: old, withDestinationURL: tool)
        let new = bin.appendingPathComponent("colctl")
        if (try? files.destinationOfSymbolicLink(atPath: new.path)) == nil, !files.fileExists(atPath: new.path) {
            try? files.createSymbolicLink(at: new, withDestinationURL: tool)
        }
    }

    /// An Islet.app left beside the new Col.app, from a download dragged next to it: an older copy of this same app,
    /// which would only show twice in Launchpad and Spotlight. It goes to the Trash.
    private static func trashOlderCopies() {
        let files = FileManager.default
        let bundle = Bundle.main.bundleURL
        let folders = Set([bundle.deletingLastPathComponent().path, "/Applications"])
        for folder in folders {
            let copy = URL(fileURLWithPath: folder).appendingPathComponent("\(legacy).app")
            guard copy.path != bundle.path, let other = Bundle(url: copy), other.bundleIdentifier == Bundle.main.bundleIdentifier,
                  isOlder(other, than: Bundle.main)
            else { continue }
            try? files.trashItem(at: copy, resultingItemURL: nil)
        }
    }

    /// Whether a copy of the app is an older version than this one.
    public static func isOlder(_ bundle: Bundle, than other: Bundle) -> Bool {
        let version = { (bundle: Bundle) in bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
        return isOlder(version(bundle), than: version(other))
    }

    /// Versions compared number by number: 1.10.0 comes after 1.9.2.
    nonisolated static func isOlder(_ version: String, than other: String) -> Bool {
        version.compare(other, options: .numeric) == .orderedAscending
    }
}
