import AppKit
import ColCore
import SwiftUI

/// Widgets under the clock of the Lock Screen: what is playing, a running timer, the battery while charging.
/// The window exists only while the Mac is locked.
@MainActor
final class LockScreenWidgets {
    private let media: MediaController
    private let timer: TimerModel
    private let power: PowerMonitor
    private var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    init(media: MediaController, timer: TimerModel, power: PowerMonitor) {
        self.media = media
        self.timer = timer
        self.power = power
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

    private func show() {
        guard Preferences.showsOnLockScreen, window == nil,
              let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
        else { return }
        let size = CGSize(width: 380, height: 150)
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.minY + screen.frame.height * 0.16,
            width: size.width, height: size.height
        )
        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = NSHostingView(rootView: LockScreenWidgetView(media: media, timer: timer, power: power))
        window.orderFrontRegardless()
        LockScreenSpace.shared?.adopt(window)
        self.window = window
    }

    private func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

struct LockScreenWidgetView: View {
    let media: MediaController
    let timer: TimerModel
    let power: PowerMonitor

    var body: some View {
        VStack(spacing: 8) {
            if media.hasPlayer {
                HStack(spacing: 14) {
                    Group {
                        if let artwork = media.artwork {
                            Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.white.opacity(0.15)
                        }
                    }
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.black.opacity(0.35)))
            }
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
            }
            .font(.system(size: 13, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .environment(\.colorScheme, .dark)
    }
}
