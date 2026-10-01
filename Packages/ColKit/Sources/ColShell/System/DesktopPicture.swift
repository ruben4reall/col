import AppKit
import ImageIO

/// The picture on a screen's desktop, for previews drawn on the user's own wallpaper.
///
/// macOS keeps the choice in the wallpaper store. Pictures it keeps as files Col may read are used as they are; a
/// dynamic wallpaper gives its downloaded picture, or its thumbnail. A wallpaper from Photos, an aerial video, or a
/// file in a protected folder Col has not been allowed into falls back to the Mac's default wallpaper, never to a
/// permission prompt.
@MainActor
enum DesktopPicture {
    /// Decoded pictures, kept while a window shows them.
    private static var cache: [URL: CGImage] = [:]

    static func forgetImages() {
        cache.removeAll()
    }

    /// The wallpaper of `screen`, decoded at most at the screen's own resolution.
    static func image(for screen: NSScreen, dark: Bool) -> CGImage? {
        let pixels = Int(max(screen.frame.width, screen.frame.height) * screen.backingScaleFactor)
        for url in candidates(for: screen) {
            if let image = cache[url] { return image }
            if let image = decode(url, maxPixels: pixels, dark: dark) {
                cache[url] = image
                return image
            }
        }
        return nil
    }

    /// Where to look, best first.
    static func candidates(for screen: NSScreen) -> [URL] {
        var urls: [URL] = []
        // `-ColWallpaper <file>` draws previews on that picture, for screenshots that must not show the user's own.
        if let path = UserDefaults.standard.string(forKey: "ColWallpaper") { urls.append(URL(fileURLWithPath: path)) }
        urls += storeChoices(for: screen)
        if let url = NSWorkspace.shared.desktopImageURL(for: screen) { urls.append(url) }
        urls.append(URL(fileURLWithPath: "/System/Library/CoreServices/DefaultDesktop.heic"))
        return urls.filter(isReadableWithoutPrompt)
    }

    // MARK: The wallpaper store

    /// The pictures the wallpaper store lists for this display, the screen's own choices before the shared ones.
    private static func storeChoices(for screen: NSScreen) -> [URL] {
        let store = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard let data = try? Data(contentsOf: store),
              let index = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [] }
        let display = displayUUID(screen)
        var desktops: [[String: Any]] = []
        for space in (index["Spaces"] as? [String: Any] ?? [:]).values {
            if let display, let entry = ((space as? [String: Any])?["Displays"] as? [String: Any])?[display] as? [String: Any],
               let desktop = entry["Desktop"] as? [String: Any] {
                desktops.append(desktop)
            }
        }
        if let display, let entry = (index["Displays"] as? [String: Any])?[display] as? [String: Any], let desktop = entry["Desktop"] as? [String: Any] {
            desktops.append(desktop)
        }
        for key in ["AllSpacesAndDisplays", "SystemDefault"] {
            if let desktop = (index[key] as? [String: Any])?["Desktop"] as? [String: Any] { desktops.append(desktop) }
        }
        return desktops.compactMap { pictureURL(in: $0) }
    }

    private static func pictureURL(in desktop: [String: Any]) -> URL? {
        guard let choice = ((desktop["Content"] as? [String: Any])?["Choices"] as? [[String: Any]])?.first,
              let configuration = choice["Configuration"] as? Data,
              let settings = try? PropertyListSerialization.propertyList(from: configuration, format: nil) as? [String: Any],
              let relative = (settings["url"] as? [String: Any])?["relative"] as? String,
              let url = URL(string: relative), url.isFileURL
        else { return nil }
        return url.pathExtension == "madesktop" ? dynamicPicture(url) : url
    }

    /// A dynamic wallpaper describes itself in a small property list: its picture once downloaded, else its thumbnail.
    private static func dynamicPicture(_ description: URL) -> URL? {
        guard let data = try? Data(contentsOf: description),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        if let asset = info["mobileAssetID"] as? String {
            let assets = URL(fileURLWithPath: "/System/Library/AssetsV2/com_apple_MobileAsset_DesktopPicture")
            let folders = (try? FileManager.default.contentsOfDirectory(at: assets, includingPropertiesForKeys: nil)) ?? []
            for folder in folders {
                let picture = folder.appendingPathComponent("AssetData/\(asset).heic")
                if FileManager.default.fileExists(atPath: picture.path) { return picture }
            }
        }
        return (info["thumbnailPath"] as? String).map { URL(fileURLWithPath: $0) }
    }

    private static func displayUUID(_ screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    // MARK: Reading

    /// Desktop, Documents and Downloads ask the user before an app may read them: Downloads is read only once Col
    /// watches it (the user has already answered), the others never.
    private static func isReadableWithoutPrompt(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(home + "/Desktop/") || path.hasPrefix(home + "/Documents/") || path.hasPrefix(home + "/Library/Mobile Documents/") {
            return false
        }
        if path.hasPrefix(home + "/Downloads/"), !Preferences.watchesDownloads { return false }
        if path.hasPrefix("/Volumes/") { return false }
        return FileManager.default.isReadableFile(atPath: path)
    }

    /// A picture with a light and a dark version gives the one that matches the appearance.
    private static func decode(_ url: URL, maxPixels: Int, dark: Bool) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        let index = dark && count > 1 ? 1 : 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }
}
