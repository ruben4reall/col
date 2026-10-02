import ColCore
import SwiftUI

/// The player in the open island: the cover, the track, a scrubber and the transport controls.
struct MediaPlayerView: View {
    let media: MediaController
    let audio: AudioMonitor

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ArtworkView(media: media)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(media.nowPlaying.title)
                            .font(Theme.Font.title)
                            .foregroundStyle(.white)
                        Text(media.nowPlaying.artist)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    OutputPicker(audio: audio)
                }
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: media.nowPlaying.trackKey)
                Spacer(minLength: 10)
                PlaybackScrubber(media: media)
                Spacer(minLength: 8)
                TransportControls(media: media)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }
}

struct ArtworkView: View {
    let media: MediaController
    var size: CGFloat = 92
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let artwork = media.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.33, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.174, style: .continuous))
            .shadow(color: media.tint.color.opacity(0.45), radius: size * 0.2, y: size * 0.065)
            // Like a record that rests: the cover draws back a little while paused.
            .scaleEffect(media.nowPlaying.isPlaying ? 1 : 0.9)
            .brightness(hovering ? 0.06 : 0)

            if let icon = media.playerIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: size * 0.28, height: size * 0.28)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                    .offset(x: size * 0.076, y: size * 0.076)
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.3), value: media.nowPlaying.isPlaying)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture { media.openPlayer() }
        .help(media.playerName)
    }
}

struct PlaybackScrubber: View {
    let media: MediaController
    /// Narrower times, for the half-width player.
    var compact = false
    @State private var dragged: Double?
    @State private var hovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = media.nowPlaying.duration
            let position = dragged ?? media.nowPlaying.position(at: context.date)
            HStack(spacing: compact ? 7 : 10) {
                Text(Self.format(position))
                    .frame(width: compact ? 30 : 38, alignment: .leading)
                GeometryReader { geometry in
                    let fraction = duration > 0 ? min(max(position / duration, 0), 1) : 0
                    let thickness: CGFloat = hovering || dragged != nil ? 7 : 5
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.16))
                        Capsule()
                            .fill(media.tint.color)
                            .frame(width: max(thickness, geometry.size.width * fraction))
                    }
                    .frame(height: thickness)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard duration > 0 else { return }
                                dragged = min(max(value.location.x / geometry.size.width, 0), 1) * duration
                            }
                            .onEnded { _ in
                                if let dragged { media.seek(to: dragged) }
                                dragged = nil
                            }
                    )
                    .animation(.spring(duration: 0.25, bounce: 0.2), value: thickness)
                }
                .frame(height: 14)
                Text("-" + Self.format(max(duration - position, 0)))
                    .frame(width: compact ? 34 : 42, alignment: .trailing)
            }
            .font(Theme.Font.figure)
            .foregroundStyle(Theme.tertiaryText)
            .opacity(duration > 0 ? 1 : 0.4)
        }
        .onHover { hovering = $0 }
    }

    static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600, minutes = total / 60 % 60, rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}

struct TransportControls: View {
    let media: MediaController
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 34 * scale) {
            ControlButton(symbol: "backward.fill", size: 17 * scale) { media.previousTrack() }
            ControlButton(symbol: media.nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 25 * scale) {
                media.togglePlayback()
            }
            ControlButton(symbol: "forward.fill", size: 17 * scale) { media.nextTrack() }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The player in half a page: the cover and the track on top, the scrubber, then the controls.
struct CompactPlayerView: View {
    let media: MediaController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ArtworkView(media: media, size: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text(media.nowPlaying.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(media.nowPlaying.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: media.nowPlaying.trackKey)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 8)
            PlaybackScrubber(media: media, compact: true)
            Spacer(minLength: 2)
            TransportControls(media: media, scale: 0.82)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Where the sound goes: every output device, the current one ticked.
private struct OutputPicker: View {
    let audio: AudioMonitor
    @State private var devices: [AudioMonitor.Device] = []
    @State private var hovering = false

    var body: some View {
        Menu {
            ForEach(devices) { device in
                Button {
                    audio.setOutput(device.id)
                } label: {
                    Label(device.name, systemImage: device.id == audio.output?.id ? "checkmark" : SystemGlyphs.audioDevice(name: device.name, transport: device.transport))
                }
            }
        } label: {
            Image(systemName: SystemGlyphs.audioDevice(name: audio.output?.name ?? "", transport: audio.output?.transport ?? .builtIn) == "laptopcomputer" ? "airplayaudio" : SystemGlyphs.audioDevice(name: audio.output?.name ?? "", transport: audio.output?.transport ?? .builtIn))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.5))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(hovering ? 0.1 : 0)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .onAppear { devices = audio.outputDevices() }
        .help(Text("Output", bundle: .module))
    }
}

/// A borderless control: a soft disc appears under the pointer, and the symbol springs when pressed.
struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size * 1.9, height: size * 1.9)
                .background(Circle().fill(.white.opacity(hovering ? 0.1 : 0)))
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.84 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.4), value: configuration.isPressed)
    }
}

extension RGBA {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}
