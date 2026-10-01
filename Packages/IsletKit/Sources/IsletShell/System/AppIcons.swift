import AppKit
import IsletCore

/// The icons of the apps behind what the island shows: the icon of the app installed, asked of the app as the Dock does,
/// else the brand's logo Islet carries (`Resources/Marks`, credited in THIRD-PARTY-NOTICES.md). When copies of an app
/// share an identifier, a renamed duplicate say, the one named as the app wins, then the one in Applications.
///
/// An app's icon holds every size up to 1024 pixels, 4 MB each once drawn. Islet keeps none of that: each icon is drawn
/// once at the size it shows, a few steps shared by the wing, the pages and the settings, and only that bitmap is kept,
/// 16 KB for 64 pixels.
@MainActor
enum AppIcons {
    private struct Key: Hashable {
        var icon: AppIcon
        var pixels: Int
    }

    private static var drawn: [Key: CGImage] = [:]
    private static var missing: Set<AppIcon> = []
    private static let steps = [32, 48, 64, 96, 128, 256]

    /// The copy of the app to show and to open, if one is installed.
    static func url(for icon: AppIcon) -> URL? {
        for identifier in icon.bundleIdentifiers {
            let copies = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: identifier)
            if let best = copies.min(by: { rank($0, name: icon.name) < rank($1, name: icon.name) }) { return best }
        }
        return nil
    }

    private static func rank(_ url: URL, name: String?) -> Int {
        var rank = 0
        if let name, url.deletingPathExtension().lastPathComponent != name { rank += 2 }
        if !url.path.hasPrefix("/Applications/") { rank += 1 }
        return rank
    }

    /// The app's icon for a square of `side` points, or its brand's logo; nil when Islet has neither.
    static func image(for icon: AppIcon, side: CGFloat, scale: CGFloat) -> CGImage? {
        let pixels = steps.first { CGFloat($0) >= side * scale } ?? steps[steps.count - 1]
        let key = Key(icon: icon, pixels: pixels)
        if let image = drawn[key] { return image }
        guard !missing.contains(icon) else { return nil }
        let source: NSImage? = if let url = url(for: icon) {
            NSWorkspace.shared.icon(forFile: url.path)
        } else if let mark = icon.mark, let url = Bundle.module.url(forResource: "mark-" + mark, withExtension: "png") {
            NSImage(contentsOf: url)
        } else {
            nil
        }
        guard let source else {
            missing.insert(icon)
            return nil
        }
        let image = draw(source, pixels: pixels)
        drawn[key] = image
        return image
    }

    /// Whether Islet carries this logo.
    static func carries(mark: String) -> Bool {
        Bundle.module.url(forResource: "mark-" + mark, withExtension: "png") != nil
    }

    private static func draw(_ icon: NSImage, pixels: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.displayP3),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        icon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    /// Forgets what was found: apps were installed or removed.
    static func forget() {
        drawn = [:]
        missing = []
    }
}
