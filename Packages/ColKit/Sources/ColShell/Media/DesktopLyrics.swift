import AppKit
import ColCore
import Observation
import SwiftUI

/// The line being sung on the desktop, large, with the next one small below it: above the wallpaper, below the
/// desktop's icons and every window, on the main screen. Clicks go through it, and it never takes the focus. It shows
/// only while music plays with synced lyrics, and fades away a few seconds after a pause. Off by default.
@MainActor
final class DesktopLyrics {
    private let media: MediaController
    private let lyrics: LyricsModel
    private var window: NSPanel?
    private var observers: [NSObjectProtocol] = []
    private var running = false
    private var fade: Task<Void, Never>?
    /// The lyrics view counts as a watcher of the lyrics while the window shows.
    private var watching = false

    /// Seconds a pause leaves the lyrics on the desktop before they fade.
    private static let pauseLinger: Duration = .seconds(4)

    init(media: MediaController, lyrics: LyricsModel) {
        self.media = media
        self.lyrics = lyrics
    }

    func start() {
        running = true
        observers = [
            NotificationCenter.default.addObserver(forName: Preferences.didChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.preferencesChanged() }
            },
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.place() }
            },
        ]
        follow()
    }

    func stop() {
        running = false
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        close()
    }

    /// Watches what decides whether the lyrics show: the player, its state and the lyrics found. Observation calls
    /// back once per change; nothing runs in between.
    private func follow() {
        guard running else { return }
        withObservationTracking {
            _ = media.nowPlaying.isPlaying
            _ = media.hasPlayer
            _ = lyrics.lyrics
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.follow()
            }
        }
        update()
    }

    private var wanted: Bool {
        Preferences.showsLyrics && Preferences.showsLyricsOnDesktop && media.hasPlayer && lyrics.lyrics?.isSynced == true
    }

    private func update() {
        guard running else { return }
        guard wanted else {
            hide(after: nil)
            return
        }
        if media.nowPlaying.isPlaying {
            fade?.cancel()
            fade = nil
            show()
        } else if window != nil, fade == nil {
            hide(after: Self.pauseLinger)
        }
    }

    private func preferencesChanged() {
        window?.sharingType = Preferences.hiddenFromScreenCapture ? .none : .readOnly
        if let window, let content = window.contentView as? NSHostingView<DesktopLyricsView> {
            content.rootView = DesktopLyricsView(lyrics: lyrics, media: media, position: Preferences.desktopLyricsPosition, size: Preferences.desktopLyricsSize)
        }
        place()
        update()
    }

    private static var screen: NSScreen? { NSScreen.screens.first }

    private func show() {
        if window == nil {
            guard let screen = Self.screen else { return }
            let frame = DesktopLyricsLayout.frame(position: Preferences.desktopLyricsPosition, size: Preferences.desktopLyricsSize, visible: screen.visibleFrame)
            let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            // Just above the wallpaper: under the desktop's icons, and under every window.
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            window.sharingType = Preferences.hiddenFromScreenCapture ? .none : .readOnly
            window.contentView = NSHostingView(rootView: DesktopLyricsView(
                lyrics: lyrics, media: media, position: Preferences.desktopLyricsPosition, size: Preferences.desktopLyricsSize
            ))
            window.alphaValue = 0
            window.orderFrontRegardless()
            self.window = window
            if !watching {
                watching = true
                lyrics.watch()
            }
        }
        animateAlpha(to: 1)
    }

    /// Fades the lyrics out, after a pause's lingering, then lets the window go.
    private func hide(after delay: Duration?) {
        guard window != nil else { return }
        fade?.cancel()
        fade = Task { @MainActor [weak self] in
            if let delay { try? await Task.sleep(for: delay) }
            guard let self, !Task.isCancelled else { return }
            self.animateAlpha(to: 0)
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { return }
            self.close()
        }
    }

    private func animateAlpha(to value: CGFloat) {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.2 : 0.6
            window.animator().alphaValue = value
        }
    }

    private func close() {
        fade = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        if watching {
            watching = false
            lyrics.unwatch()
        }
    }

    private func place() {
        guard let window, let screen = Self.screen else { return }
        let frame = DesktopLyricsLayout.frame(position: Preferences.desktopLyricsPosition, size: Preferences.desktopLyricsSize, visible: screen.visibleFrame)
        window.setFrame(frame, display: true)
    }
}

/// The lyrics on the desktop: white words with a soft shadow, legible on any wallpaper without a box around them.
struct DesktopLyricsView: View {
    let lyrics: LyricsModel
    let media: MediaController
    let position: DesktopLyricsPosition
    let size: DesktopLyricsSize

    var body: some View {
        if let shown = lyrics.lyrics, shown.isSynced {
            LyricsReel(lyrics: shown, current: lyrics.current, playing: media.nowPlaying.isPlaying,
                       position: { lyrics.position(at: $0) }, before: 0, after: 1, size: size.lineSize,
                       otherScale: 0.5, alignment: alignment, anchor: 0, anchorsTop: true, spacing: size.lineSize * 0.3, onWallpaper: true)
                .padding(.horizontal, size.lineSize * 0.4)
                .environment(\.colorScheme, .dark)
        }
    }

    private var alignment: HorizontalAlignment {
        switch position {
        case .lowerLeft: .leading
        case .lowerRight: .trailing
        case .center, .lowerCenter: .center
        }
    }
}
