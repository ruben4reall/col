import AppKit
import ColCore
import Observation

/// What is playing, its artwork and colour, and the commands to control it.
@MainActor
@Observable
final class MediaController {
    private(set) var nowPlaying = NowPlaying()
    private(set) var artwork: NSImage?
    @ObservationIgnored private(set) var artworkImage: CGImage?
    /// A vivid colour taken from the artwork, for the equalizer and the progress bar.
    private(set) var tint: RGBA = .white
    private(set) var playerIcon: NSImage?
    private(set) var playerName = ""

    /// Called after every change, for the island to update its live activity.
    @ObservationIgnored var onChange: ((_ trackChanged: Bool) -> Void)?
    @ObservationIgnored private let bridge = MediaBridge()
    @ObservationIgnored private var lastPID: Int32 = 0

    var hasPlayer: Bool { !nowPlaying.isEmpty }

    func start() {
        bridge.onUpdate = { [weak self] update in self?.apply(update) }
        bridge.start()
    }

    func stop() {
        bridge.stop()
    }

    private func apply(_ update: NowPlayingUpdate) {
        let previousTrack = nowPlaying.trackKey
        switch nowPlaying.apply(update) {
        case .unchanged:
            break
        case .removed:
            setArtwork(nil)
        case .replaced(let data):
            setArtwork(ArtworkProcessor.thumbnail(from: data))
        }
        if nowPlaying.pid != lastPID {
            lastPID = nowPlaying.pid
            let app = NSRunningApplication(processIdentifier: nowPlaying.pid)
            playerIcon = app?.icon
            playerName = app?.localizedName ?? ""
        }
        let trackChanged = nowPlaying.trackKey != previousTrack && !previousTrack.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        onChange?(trackChanged)
    }

    private func setArtwork(_ image: CGImage?) {
        artworkImage = image
        artwork = image.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        tint = image.flatMap(ArtworkProcessor.tint(of:)) ?? .white
    }

    // MARK: Commands

    /// Commands update the island at once and let the bridge confirm, so the controls never feel late.
    func togglePlayback() {
        nowPlaying.setPlaying(!nowPlaying.isPlaying, at: Date())
        bridge.send("toggle")
        onChange?(false)
    }

    func nextTrack() { bridge.send("next") }
    func previousTrack() { bridge.send("previous") }

    func seek(to position: Double) {
        nowPlaying.seek(to: position, at: Date())
        bridge.send("seek \(position)")
        onChange?(false)
    }

    func openPlayer() {
        NSRunningApplication(processIdentifier: nowPlaying.pid)?.activate()
    }
}

enum ArtworkProcessor {
    /// Decodes the artwork straight to a small bitmap: a 1000 pixel cover would otherwise cost 4 MB for a 22 point
    /// thumbnail and an 84 point cover.
    static func thumbnail(from data: Data, maxPixels: Int = 256) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The most vivid colour of the artwork, lifted so it reads on black.
    static func tint(of image: CGImage) -> RGBA? {
        let side = 12
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        var best: (score: Double, color: RGBA)?
        var sum = (red: 0.0, green: 0.0, blue: 0.0)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[index]) / 255, green = Double(pixels[index + 1]) / 255, blue = Double(pixels[index + 2]) / 255
            sum.red += red; sum.green += green; sum.blue += blue
            let high = max(red, green, blue), low = min(red, green, blue)
            let saturation = high > 0 ? (high - low) / high : 0
            let score = saturation * 0.7 + high * 0.3
            if best == nil || score > best!.score { best = (score, RGBA(red: red, green: green, blue: blue)) }
        }
        let count = Double(side * side)
        let fallback = RGBA(red: sum.red / count, green: sum.green / count, blue: sum.blue / count)
        let chosen = (best?.score ?? 0) > 0.35 ? best!.color : fallback
        return lifted(chosen)
    }

    /// Raises dark colours to a readable brightness while keeping their hue.
    static func lifted(_ color: RGBA) -> RGBA {
        let high = max(color.red, color.green, color.blue)
        guard high < 0.75 else { return color }
        if high < 0.05 { return .white }
        let gain = 0.75 / high
        return RGBA(red: min(color.red * gain, 1), green: min(color.green * gain, 1), blue: min(color.blue * gain, 1))
    }
}
