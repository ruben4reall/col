import AppKit

/// Where this copy of Col runs from. Some places are only passing through: the disk image it came on, or the read-only
/// copy macOS runs a downloaded app from until it is moved (App Translocation). The command's links, the login item and
/// the Trash must never act on those: once the image is ejected, what they point at is gone.
@MainActor
public enum AppLocation {
    private typealias IsTranslocated = @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> UInt8
    private typealias OriginalPath = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?

    /// Security's translocation functions, looked up at run time: they are not in its public headers.
    private static let translocation: (isTranslocated: IsTranslocated, originalPath: OriginalPath)? = {
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let isTranslocated = dlsym(handle, "SecTranslocateIsTranslocatedURL"),
              let originalPath = dlsym(handle, "SecTranslocateCreateOriginalPathForURL")
        else { return nil }
        return (unsafeBitCast(isTranslocated, to: IsTranslocated.self), unsafeBitCast(originalPath, to: OriginalPath.self))
    }()

    /// Whether macOS runs this copy translocated, from a read-only copy of where the user put it.
    public static var isTranslocated: Bool { isTranslocated(Bundle.main.bundleURL) }

    private static func isTranslocated(_ url: URL) -> Bool {
        if let translocation {
            var translocated = false
            if translocation.isTranslocated(url as CFURL, &translocated, nil) != 0 { return translocated }
        }
        return url.pathComponents.contains("AppTranslocation")
    }

    /// The app where the user put it: the bundle itself or, when it runs translocated, the one it was copied from.
    public static var bundleURL: URL {
        let url = Bundle.main.bundleURL
        guard isTranslocated(url), let original = translocation?.originalPath(url as CFURL, nil)?.takeRetainedValue() else {
            return url
        }
        return original as URL
    }

    /// Whether the app runs from a place it stays: not translocated, and not from a read-only volume such as its disk
    /// image. Applications, the Downloads folder or another disk all count.
    public static var isStable: Bool {
        let url = Bundle.main.bundleURL
        return !isTranslocated(url) && !isReadOnly(url)
    }

    /// Whether a file lives on a volume that cannot be written to, such as a mounted disk image.
    nonisolated static func isReadOnly(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true
    }

    /// Whether an app sits in an Applications folder: the Mac's, or the one in the user's home.
    public nonisolated static func isInApplications(_ url: URL, home: String = NSHomeDirectory()) -> Bool {
        let path = url.standardizedFileURL.path
        return ["/Applications/", home + "/Applications/"].contains { path.hasPrefix($0) }
    }

    /// A development build, which leaves the user's own files and the installed app alone. It runs from a build
    /// folder, or with a socket of its own (COL_SOCKET) to run beside the installed Col.
    public static var isDevelopmentBuild: Bool {
        isDevelopmentPath(Bundle.main.bundleURL.path) || !(ProcessInfo.processInfo.environment["COL_SOCKET"]?.isEmpty ?? true)
    }

    /// Build folders: SwiftPM's .build, Xcode's DerivedData, an archive, and any other folder given to xcodebuild,
    /// such as COL_BUILD_DIR for scripts/build.sh, whose apps land in Build/Products. An installed app never lives there.
    nonisolated static func isDevelopmentPath(_ path: String) -> Bool {
        ["/.build/", "/DerivedData/", "/Build/Products/", ".xcarchive/"].contains { path.contains($0) }
    }

    private nonisolated static let quarantine = "com.apple.quarantine"

    /// Whether an app carries the quarantine macOS puts on downloads, which makes it run translocated until the Finder
    /// moves it.
    public nonisolated static func isQuarantined(_ app: URL) -> Bool {
        getxattr(app.path, quarantine, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    /// Takes that quarantine off an app and everything inside it. A copy made from the disk image keeps the image's
    /// quarantine, and macOS would run it translocated again, away from where it was put. Gatekeeper has already
    /// checked this app: it is running. Returns whether the app is free of it.
    @discardableResult
    public nonisolated static func removeQuarantine(from app: URL) -> Bool {
        let root = app.path
        removexattr(root, quarantine, XATTR_NOFOLLOW)
        if let walker = FileManager.default.enumerator(atPath: root) {
            for case let item as String in walker { removexattr(root + "/" + item, quarantine, XATTR_NOFOLLOW) }
        }
        return getxattr(root, quarantine, nil, 0, 0, XATTR_NOFOLLOW) < 0 && errno == ENOATTR
    }

    /// Quits, then opens the app at this place once this process is gone (two would mean two islands on one notch),
    /// with the documents and links this launch was asked to open. Should those no longer open, the app still does.
    public static func relaunch(at bundle: URL = bundleURL, opening urls: [URL] = []) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        let script = """
            app="$0"; pid="$1"; shift
            while /bin/kill -0 "$pid" 2>/dev/null; do /bin/sleep 0.1; done
            if [ $# -gt 0 ]; then /usr/bin/open -a "$app" "$@" || /usr/bin/open "$app"; else /usr/bin/open "$app"; fi
            """
        process.arguments = ["-c", script, bundle.path, String(ProcessInfo.processInfo.processIdentifier)]
            + urls.map { $0.isFileURL ? $0.path : $0.absoluteString }
        try? process.run()
        NSApp.terminate(nil)
    }
}
