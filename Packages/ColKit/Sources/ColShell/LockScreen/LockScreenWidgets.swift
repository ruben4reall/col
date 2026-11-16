import AppKit
import ColCore
import CoreImage
import SwiftUI

/// Widgets under the clock of the Lock Screen: what is playing, a running timer, the battery while charging, the
/// weather when it is on, and, when chosen, the lyrics of the song, large. The window exists only while the Mac is
/// locked.
@MainActor
final class LockScreenWidgets {
    private let media: MediaController
    private let timer: TimerModel
    private let power: PowerMonitor
    private let lyrics: LyricsModel
    var weather: WeatherModel?
    /// The weather is kept fresh while the window shows, asked from show() and hide() once per lock, as the lyrics
    /// are: a view's own appear and disappear do not follow a window ordered out.
    private var watchesWeather = false
    private var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    /// The lyrics are followed line by line while the window shows them, and only then.
    private var watching = false

    init(media: MediaController, timer: TimerModel, power: PowerMonitor, lyrics: LyricsModel) {
        self.media = media
        self.timer = timer
        self.power = power
        self.lyrics = lyrics
    }

    func start() {
        let center = DistributedNotificationCenter.default()
        observers = [
            center.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.show() }
            },
            center.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            },
        ]
        // `-ColLockPreview YES` shows the widgets on the desktop, to work on them without locking the Mac.
        if UserDefaults.standard.bool(forKey: "ColLockPreview") { show() }
    }

    func stop() {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers = []
        hide()
    }

    /// The lyrics show when the setting is on, with lyrics on and the Lock Screen feature working.
    static var showsLyrics: Bool {
        Preferences.showsOnLockScreen && Preferences.showsLyrics && Preferences.showsLyricsOnLockScreen
    }

    private func show() {
        guard Preferences.showsOnLockScreen, window == nil,
              let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
        else { return }
        // Between the clock and the user's picture, never over the password field; a screen too short for that keeps
        // the plain widgets.
        let card = LockScreenLayout.card(screen: screen.frame)
        let withLyrics = Self.showsLyrics && card.height >= LockScreenLayout.smallestCard
        let frame: NSRect
        if withLyrics {
            frame = card
        } else {
            let size = CGSize(width: 380, height: 150)
            frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + screen.frame.height * 0.16,
                           width: size.width, height: size.height)
        }
        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = NSHostingView(rootView: LockScreenWidgetView(media: media, timer: timer, power: power, lyrics: withLyrics ? lyrics : nil, weather: weather))
        window.orderFrontRegardless()
        LockScreenSpace.shared?.adopt(window)
        self.window = window
        if withLyrics {
            watching = true
            lyrics.watch()
        }
        if Preferences.showsWeather, let weather, !watchesWeather {
            watchesWeather = true
            weather.watch()
        }
    }

    private func hide() {
        window?.orderOut(nil)
        // Torn down at once: nothing of the Lock Screen keeps running once the Mac is unlocked.
        window?.contentView = nil
        window = nil
        if watching {
            watching = false
            lyrics.unwatch()
        }
        if watchesWeather {
            watchesWeather = false
            weather?.unwatch()
        }
    }
}

struct LockScreenWidgetView: View {
    let media: MediaController
    let timer: TimerModel
    let power: PowerMonitor
    /// The lyrics to show, large, when the user chose them on the Lock Screen.
    var lyrics: LyricsModel?
    var weather: WeatherModel?

    var body: some View {
        VStack(spacing: 8) {
            if media.hasPlayer {
                if let lyrics {
                    LockScreenLyricsCard(lyrics: lyrics, media: media)
                } else {
                    LockScreenPlayer(media: media, artwork: 54)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.black.opacity(0.35)))
                }
            }
            chips
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .environment(\.colorScheme, .dark)
    }

    private var chips: some View {
        HStack(spacing: 8) {
            if let countdown = timer.countdown {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Label(Countdown.format(countdown.remaining(at: context.date)), systemImage: "timer")
                }
                .padding(.horizontal, 12).frame(height: 30)
                .background(Capsule().fill(.black.opacity(0.35)))
            }
            if let state = power.state, state.onAdapter {
                Label(state.level.formatted(.percent.precision(.fractionLength(0))), systemImage: "bolt.fill")
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(Capsule().fill(.black.opacity(0.35)))
            }
            if let weather, Preferences.showsWeather {
                LockScreenWeather(weather: weather)
            }
        }
        .font(.system(size: 13, weight: .semibold).monospacedDigit())
    }
}

/// The cover, the track and the transport controls, as the Lock Screen shows them.
struct LockScreenPlayer: View {
    let media: MediaController
    var artwork: CGFloat = 54

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let image = media.artwork {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.white.opacity(0.15)
                }
            }
            .frame(width: artwork, height: artwork)
            .clipShape(RoundedRectangle(cornerRadius: artwork * 0.22, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(media.nowPlaying.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(media.nowPlaying.artist).font(.system(size: 12.5)).opacity(0.7).lineLimit(1)
            }
            Spacer(minLength: 6)
            HStack(spacing: 14) {
                ControlButton(symbol: "backward.fill", size: 15) { media.previousTrack() }
                ControlButton(symbol: media.nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 20) { media.togglePlayback() }
                ControlButton(symbol: "forward.fill", size: 15) { media.nextTrack() }
            }
        }
    }
}

/// The lyrics of the song on the Lock Screen: the line being sung large and bright, the one before dim above it, the
/// next ones dim below, over the cover blurred and darkened so the words read on any wallpaper. The player sits at its
/// foot. Without lyrics, only the player shows.
struct LockScreenLyricsCard: View {
    let lyrics: LyricsModel
    let media: MediaController
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            // The room above the controls decides how many lines show, and how big: on the shortest screens, the
            // line being sung alone; none when even that does not fit.
            let room = geometry.size.height - 78
            let shown = room >= 44 ? lyrics.lyrics.flatMap { $0.isSynced ? $0 : nil } : nil
            let before = room >= 180 ? 1 : 0
            let after = room >= 240 ? 3 : room >= 140 ? 1 : 0
            // Alone, the line being sung takes the room for two rows of its words.
            let alone = before == 0 && after == 0
            let size = min(max(geometry.size.width * 0.046, 24), 34, max(16, room * (alone ? 0.3 : 0.16)))
            VStack(spacing: 0) {
                if let shown {
                    LyricsReel(lyrics: shown, current: lyrics.current, playing: media.nowPlaying.isPlaying,
                               position: { lyrics.position(at: $0) }, before: before, after: after, size: size,
                               anchor: before > 0 ? 0.36 : after > 0 ? 0.3 : 0.5)
                        .padding(.horizontal, 32)
                        .padding(.top, alone ? 8 : 18)
                        .mask(LinearGradient(stops: [
                            .init(color: alone ? .black : .clear, location: 0), .init(color: .black, location: 0.12),
                            .init(color: .black, location: 0.84), .init(color: alone ? .black : .clear, location: 1),
                        ], startPoint: .top, endPoint: .bottom))
                        .transition(.opacity)
                }
                LockScreenPlayer(media: media, artwork: 46)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            }
            .frame(width: geometry.size.width, height: shown == nil ? nil : geometry.size.height)
            .background { backdrop }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
            .frame(maxHeight: .infinity, alignment: .bottom)
            .animation(.easeInOut(duration: 0.4), value: shown == nil)
        }
    }

    /// The cover, blurred once and darkened; a deep shade of its colour with Reduce Transparency or without a cover.
    @ViewBuilder private var backdrop: some View {
        if !reduceTransparency, let image = media.artworkImage.flatMap(BlurredArtwork.image(for:)) {
            ZStack {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                Color.black.opacity(0.42)
            }
        } else {
            let tint = media.tint.color
            LinearGradient(colors: [tint.blended(with: .black, by: 0.62), tint.blended(with: .black, by: 0.82)], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// The cover blurred and a little more saturated, made once per cover: a backdrop that costs nothing to draw.
@MainActor
enum BlurredArtwork {
    private static var last: (source: CGImage, blurred: CGImage)?

    static func image(for source: CGImage) -> CGImage? {
        if let last, last.source === source { return last.blurred }
        let input = CIImage(cgImage: source)
        let radius = Double(max(source.width, source.height)) * 0.12
        guard let blur = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputImageKey: input.clampedToExtent(), kCIInputRadiusKey: radius]),
              let blurred = blur.outputImage?.cropped(to: input.extent),
              let colors = CIFilter(name: "CIColorControls", parameters: [kCIInputImageKey: blurred, kCIInputSaturationKey: 1.35]),
              let output = colors.outputImage,
              let image = CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: input.extent)
        else { return nil }
        last = (source, image)
        return image
    }
}

extension Color {
    /// Mixed with another colour, `amount` of the way toward it.
    func blended(with other: Color, by amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .black
        func blend(_ x: CGFloat, _ y: CGFloat) -> Double { Double(x + (y - x) * amount) }
        return Color(.sRGB, red: blend(a.redComponent, b.redComponent), green: blend(a.greenComponent, b.greenComponent),
                     blue: blend(a.blueComponent, b.blueComponent))
    }
}

/// The temperature and the sky, once a report has come.
private struct LockScreenWeather: View {
    let weather: WeatherModel

    var body: some View {
        if let report = weather.report {
            HStack(spacing: 6) {
                Image(systemName: report.symbol).symbolRenderingMode(.multicolor)
                Text(WeatherFormat.temperature(report.temperature))
            }
            .padding(.horizontal, 12).frame(height: 30)
            .background(Capsule().fill(.black.opacity(0.35)))
        }
    }
}
