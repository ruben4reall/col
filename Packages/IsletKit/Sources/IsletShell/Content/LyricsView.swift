import IsletCore
import SwiftUI

/// The lyrics beside the player, as Apple Music shows them: the line being sung bright, the others dimmer and softer
/// the farther they are, the text gliding up line by line. A tap on a line jumps the song there. Long instrumental
/// passages show three dots that breathe.
struct LyricsView: View {
    let lyrics: LyricsModel
    let media: MediaController
    let width: WidgetWidth
    @AppStorage("lyricsTextSize") private var textSize = 1

    var body: some View {
        Group {
            if let found = lyrics.lyrics {
                if found.isSynced { synced(found) } else { plain(found) }
            } else {
                Color.clear
            }
        }
        .onAppear { lyrics.watch() }
        .onDisappear { lyrics.unwatch() }
    }

    private var fontSize: CGFloat {
        let base: CGFloat = width == .full ? 17 : 15
        return base + CGFloat(textSize - 1) * 2
    }

    private func synced(_ found: Lyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: fontSize * 0.55) {
                    // Room above the first line, so it can sit on the reading line like the others.
                    Color.clear.frame(height: 30)
                    ForEach(Array(found.lines.enumerated()), id: \.element.id) { index, line in
                        LyricLineView(line: line, distance: distance(index), size: fontSize)
                            .id(index)
                            .onTapGesture { media.seek(to: line.time) }
                    }
                    Color.clear.frame(height: 90)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDisabled(true)
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                    .init(color: .black, location: 0.72), .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
            .onAppear { proxy.scrollTo(lyrics.current ?? 0, anchor: UnitPoint(x: 0, y: 0.3)) }
            .onChange(of: lyrics.current) {
                withAnimation(.spring(duration: 0.6, bounce: 0.12)) {
                    proxy.scrollTo(lyrics.current ?? 0, anchor: UnitPoint(x: 0, y: 0.3))
                }
            }
        }
    }

    /// Plain lyrics have no timing: they are shown to be read and scrolled by hand.
    private func plain(_ found: Lyrics) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(found.lines) { line in
                    Text(verbatim: line.text)
                        .font(.system(size: fontSize - 2, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// How far a line is from the one being sung: 0 for it, negative above.
    private func distance(_ index: Int) -> Int {
        guard let current = lyrics.current else { return index + 1 }
        return index - current
    }
}

private struct LyricLineView: View {
    let line: LyricLine
    let distance: Int
    let size: CGFloat

    var body: some View {
        Group {
            if line.isPause {
                BreathingDots(active: distance == 0, size: size)
            } else {
                Text(verbatim: line.text)
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(.white.opacity(opacity))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .blur(radius: blur)
                    .scaleEffect(distance == 0 ? 1 : 0.97, anchor: .leading)
            }
        }
        .animation(.easeOut(duration: 0.35), value: distance)
        .contentShape(Rectangle())
    }

    private var opacity: Double {
        switch distance {
        case 0: 1
        case ..<0: 0.32
        case 1: 0.5
        default: 0.38
        }
    }

    private var blur: CGFloat {
        distance == 0 ? 0 : min(CGFloat(abs(distance)) * 0.5, 1.6)
    }
}

/// Three dots that swell in turn while the music plays without words.
private struct BreathingDots: View {
    let active: Bool
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.35) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(.white.opacity(active ? 0.9 : 0.35))
                    .frame(width: size * 0.42, height: size * 0.42)
                    .phaseAnimator(active ? [false, true] : [false]) { dot, phase in
                        dot.scaleEffect(phase ? 1.25 : 0.8)
                    } animation: { _ in
                        .easeInOut(duration: 0.7).delay(Double(index) * 0.18)
                    }
            }
        }
        .frame(height: size * 1.2)
    }
}
