import AppKit
import ServiceManagement

/// Islet became Col with 2.0. On the first launch under the new name, everything takes it without the user noticing:
/// the app on disk, the folders it keeps, the command and the login item. Whatever was set up under Islet keeps
/// working: its links, its hooks, its scripts.
@MainActor
public enum NameChange {
    private nonisolated static let legacy = "Islet"
    private static let doneKey = "nameChangeDone"
    /// Where the app was when the login item was last registered, so that the login item follows it when it moves.
    private static let loginItemKey = "loginItemPath"

    /// Development builds leave the user's own files alone, unless `-ColMigrate YES` asks, run under a home of its own
    /// (CFFIXED_USER_HOME); then nothing is remembered, so the real move still happens later. That home redirects
    /// neither /Applications nor the login item, so those are left alone too.
    private static var forced: Bool { UserDefaults.standard.bool(forKey: "ColMigrate") }

    private static var isDevelopmentBuild: Bool { AppLocation.isDevelopmentBuild }

    /// Sparkle installs an update where the app was, under its old file name: Islet.app takes its new name, Col.app,
    /// and starts again from there with what this launch was asked to open. Returns true when it does, so launching
    /// stops here.
    ///
    /// A copy Homebrew installed keeps its name: Homebrew knows it as Islet.app, and `brew upgrade --cask --greedy col`
    /// replaces it with Col.app. So does a copy that only passes through, on its disk image or translocated.
    public static func renameBundleIfNeeded(opening urls: [URL] = []) -> Bool {
        let bundle = Bundle.main.bundleURL
        guard bundle.deletingPathExtension().lastPathComponent == legacy, !isDevelopmentBuild || forced, AppLocation.isStable,
              !Homebrew.installed(bundle)
        else { return false }
        let files = FileManager.default
        let renamed = bundle.deletingLastPathComponent().appendingPathComponent("Col.app")
        if files.fileExists(atPath: renamed.path) {
            // Another app under that name: both stay as they are.
            guard let other = Bundle(url: renamed), other.bundleIdentifier == Bundle.main.bundleIdentifier else { return false }
            if isOlder(Bundle.main, than: other) || Homebrew.installed(renamed) {
                // The Col.app beside this copy is the one to keep, newer or Homebrew's: this copy makes way for it.
                try? files.trashItem(at: bundle, resultingItemURL: nil)
                AppLocation.relaunch(at: renamed, opening: urls)
                return true
            }
            // The same version or an older one, put there before this copy updated itself: it goes to the Trash, and
            // this copy, the one the login item and the command were set up with, takes the name.
            guard (try? files.trashItem(at: renamed, resultingItemURL: nil)) != nil else { return false }
        }
        guard (try? files.moveItem(at: bundle, to: renamed)) != nil else { return false }
        AppLocation.relaunch(at: renamed, opening: urls)
        return true
    }

    /// Moves what Islet kept to Col's folders, once, before anything reads them. What depends on where the app lives
    /// (the command's links, the login item, older copies) waits for a launch from a place the app stays: run from its
    /// disk image or translocated, it would point at something about to vanish. From there, at every launch, the
    /// links and the login item follow the app.
    public static func migrateIfNeeded() {
        guard !isDevelopmentBuild || forced else { return }
        let defaults = UserDefaults.standard
        let stable = AppLocation.isStable
        if !defaults.bool(forKey: doneKey) || forced {
            let files = FileManager.default
            for directory in [FileManager.SearchPathDirectory.applicationSupportDirectory, .cachesDirectory] {
                let base = files.urls(for: directory, in: .userDomainMask)[0]
                move(base.appendingPathComponent(legacy, isDirectory: true), into: base.appendingPathComponent("Col", isDirectory: true))
            }
            // The socket Islet left, now in Col's folder: nothing answers on it.
            let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Col")
            try? files.removeItem(at: support.appendingPathComponent("islet.sock"))
            carrySettings(defaults)

            if stable {
                relinkCommand()
                trashOlderCopies()
                if !forced {
                    // The login item was registered for Islet.app.
                    followLoginItem(defaults, registerAgain: true)
                    defaults.set(true, forKey: doneKey)
                }
            }
        }
        guard stable else { return }
        repairCommandLinks()
        if !forced { followLoginItem(defaults, registerAgain: false) }
    }

    /// Islet's settings that changed name.
    nonisolated static func carrySettings(_ defaults: UserDefaults) {
        let frame = "NSWindow Frame ColFloatingPrompter"
        if defaults.object(forKey: frame) == nil, let old = defaults.object(forKey: "NSWindow Frame IsletFloatingPrompter") {
            defaults.set(old, forKey: frame)
        }
    }

    /// Moves a folder to its new place. When both exist, what the old one holds joins the new one, folder by folder;
    /// nothing already there is replaced, and an old folder left empty goes. Links are moved as links, never followed.
    nonisolated static func move(_ old: URL, into new: URL) {
        let files = FileManager.default
        guard let type = (try? files.attributesOfItem(atPath: old.path))?[.type] as? FileAttributeType else { return }
        var isFolder: ObjCBool = false
        guard files.fileExists(atPath: new.path, isDirectory: &isFolder) || (try? files.destinationOfSymbolicLink(atPath: new.path)) != nil
        else {
            try? files.moveItem(at: old, to: new)
            return
        }
        guard type == .typeDirectory, isFolder.boolValue else { return }
        for item in (try? files.contentsOfDirectory(at: old, includingPropertiesForKeys: nil)) ?? [] {
            move(item, into: new.appendingPathComponent(item.lastPathComponent))
        }
        if let left = try? files.contentsOfDirectory(atPath: old.path), left.allSatisfy({ $0 == ".DS_Store" }) {
            try? files.removeItem(at: old)
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

    /// The hooks of every agent call ~/.local/bin/islet or ~/.local/bin/colctl. When the app they lead to is gone
    /// (moved, renamed, replaced by Homebrew, ejected with its disk image) or is a copy that goes away, they lead here
    /// again. Checked at each launch: two links read, nothing else.
    private static func repairCommandLinks() {
        guard let tool = CommandLineInstaller.bundledTool else { return }
        let files = FileManager.default
        let bin = files.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")
        for name in ["islet", "colctl"] {
            let link = bin.appendingPathComponent(name)
            guard linkNeedsRepair(link, tool: tool) else { continue }
            try? files.removeItem(at: link)
            try? files.createSymbolicLink(at: link, withDestinationURL: tool)
        }
    }

    /// Whether a link of the command must lead to this copy's `tool` instead: what it leads to is gone, or lies in an
    /// Islet.app, a translocated copy or a disk image. A link to another working command is left alone, and so is
    /// anything that is not a link.
    nonisolated static func linkNeedsRepair(_ link: URL, tool: URL) -> Bool {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return false }
        let target = URL(fileURLWithPath: destination, relativeTo: link.deletingLastPathComponent()).standardizedFileURL
        guard target.path != tool.standardizedFileURL.path else { return false }
        guard FileManager.default.isExecutableFile(atPath: target.path) else { return true }
        let components = target.pathComponents
        return components.contains("\(legacy).app") || components.contains("AppTranslocation") || AppLocation.isReadOnly(target)
    }

    /// The login item opens the app from where it was registered. When the app has moved since (renamed, replaced by
    /// Homebrew under its new name, dragged elsewhere), it is registered again from here. The first time a place is
    /// seen, it is only noted, unless `registerAgain` asks: macOS tells the user each time an app registers one.
    private static func followLoginItem(_ defaults: UserDefaults, registerAgain: Bool) {
        let path = Bundle.main.bundleURL.path
        let registered = defaults.string(forKey: loginItemKey)
        guard registered != path else { return }
        defaults.set(path, forKey: loginItemKey)
        guard registerAgain || registered != nil, SMAppService.mainApp.status == .enabled else { return }
        try? SMAppService.mainApp.unregister()
        try? SMAppService.mainApp.register()
    }

    /// An Islet.app left beside the new Col.app, or in Applications, from a download dragged next to it: an older copy
    /// of this same app, which would only show twice in Launchpad and Spotlight. It goes to the Trash, unless Homebrew
    /// installed it: Homebrew replaces that one itself.
    private static func trashOlderCopies() {
        let files = FileManager.default
        let bundle = Bundle.main.bundleURL
        let folders = Set([bundle.deletingLastPathComponent().path] + (forced ? [] : ["/Applications"]))
        for folder in folders {
            let copy = URL(fileURLWithPath: folder).appendingPathComponent("\(legacy).app")
            guard copy.path != bundle.path, let other = Bundle(url: copy), other.bundleIdentifier == Bundle.main.bundleIdentifier,
                  isOlder(other, than: Bundle.main), !Homebrew.installed(copy)
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
