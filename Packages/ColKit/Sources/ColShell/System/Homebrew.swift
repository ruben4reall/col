import Foundation

/// What Homebrew installed. A cask moves the app into the applications folder (the app itself is not kept in
/// Homebrew's folders), records it in <prefix>/Caskroom/<token>, leaves a link to the app beside each version there,
/// and links its commands into <prefix>/bin. A copy Homebrew installed keeps its name and its place: renamed or thrown
/// away, it would make `brew upgrade` and `brew uninstall` fail, since Homebrew looks for it where it put it.
enum Homebrew {
    /// Apple silicon's prefix, then Intel's.
    static let prefixes = ["/opt/homebrew", "/usr/local"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    /// Islet's cask, and Col's, which takes over its record when the tap renames it.
    private static let tokens = ["islet", "col"]
    /// The commands these casks link into <prefix>/bin.
    private static let commands = ["islet", "colctl"]

    /// Whether one of these casks installed the app at this place.
    static func installed(_ app: URL, prefixes: [URL] = prefixes) -> Bool {
        let files = FileManager.default
        let path = canonical(app)
        let name = app.lastPathComponent
        for prefix in prefixes {
            let rooms = tokens.map { prefix.appendingPathComponent("Caskroom/\($0)", isDirectory: true) }
                .filter { files.fileExists(atPath: $0.path) }
            guard !rooms.isEmpty else { continue }
            for room in rooms {
                let versions = (try? files.contentsOfDirectory(at: room, includingPropertiesForKeys: nil)) ?? []
                // Beside each version, the link Homebrew leaves to the app it moved.
                if versions.contains(where: { destination(of: $0.appendingPathComponent(name)) == path }) { return true }
                // The record names the app, and the cask was installed to the folder it is in.
                if records(name, in: room), canonical(applicationsFolder(of: room).appendingPathComponent(name)) == path { return true }
            }
            // The cask's commands, linked into the app.
            if commands.contains(where: { destination(of: prefix.appendingPathComponent("bin/\($0)"))?.hasPrefix(path + "/") == true }) {
                return true
            }
        }
        return false
    }

    /// Homebrew's link to the command inside this app, in a prefix where one of these casks is installed: the link of
    /// that name, else the other one. `brew upgrade` points it at the app that replaces this one, which Col, quit for
    /// the upgrade and not opened again, could not do for its own links.
    static func command(_ name: String, into app: URL, prefixes: [URL] = prefixes) -> URL? {
        let files = FileManager.default
        let path = canonical(app)
        for prefix in prefixes where tokens.contains(where: { files.fileExists(atPath: prefix.appendingPathComponent("Caskroom/\($0)").path) }) {
            for command in [name] + commands.filter({ $0 != name }) {
                let link = prefix.appendingPathComponent("bin/\(command)")
                if destination(of: link)?.hasPrefix(path + "/") == true, files.isExecutableFile(atPath: link.path) { return link }
            }
        }
        return nil
    }

    /// Whether the cask's record installs an app of this name: its receipt, or the cask file kept for each version.
    private static func records(_ name: String, in room: URL) -> Bool {
        let quoted = "\"\(name)\""
        guard let walker = FileManager.default.enumerator(at: room.appendingPathComponent(".metadata"), includingPropertiesForKeys: nil) else {
            return false
        }
        for case let file as URL in walker where ["json", "rb"].contains(file.pathExtension) && file.lastPathComponent != "config.json" {
            if let text = try? String(contentsOf: file, encoding: .utf8), text.contains(quoted) { return true }
        }
        return false
    }

    /// The applications folder the cask was installed to: the one given with `--appdir`, else Homebrew's default.
    private static func applicationsFolder(of room: URL) -> URL {
        if let data = try? Data(contentsOf: room.appendingPathComponent(".metadata/config.json")),
           let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for scope in ["explicit", "default"] {
                if let folder = (config[scope] as? [String: Any])?["appdir"] as? String {
                    return URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
                }
            }
        }
        return URL(fileURLWithPath: "/Applications", isDirectory: true)
    }

    /// Where a link leads, or nil when it is not one.
    private static func destination(of link: URL) -> String? {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return nil }
        return canonical(URL(fileURLWithPath: destination, relativeTo: link.deletingLastPathComponent()))
    }

    private static func canonical(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
