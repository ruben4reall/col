import ColCore
import SwiftUI

/// The lyrics beside the player, as Apple Music shows them: the line being sung bright, the others dimmer and softer
/// the farther they are, the text gliding up line by line. Lyrics timed word by word fill as they are sung. A tap on a
/// line jumps the song there. Long instrumental passages show three dots that breathe.
///
/// A small menu fixes lyrics that are wrong: their timing, half a second at a time, other lyrics chosen among
/// LRCLIB's, or no lyrics at all for the song.
struct LyricsView: View {
    let lyrics: LyricsModel
    let media: MediaController
    let width: WidgetWidth
    @AppStorage("lyricsTextSize") private var textSize = 1
    @State private var choosing = false
    @State private var hovering = false

    var body: some View {
        Group {
            if choosing {
                LyricsChooser(lyrics: lyrics) { choosing = false }
                    .transition(.opacity)
            } else if let found = lyrics.lyrics {
                Group {
                    if found.isSynced { synced(found) } else { plain(found) }
                }
                .overlay(alignment: .topTrailing) {
                    LyricsMenu(lyrics: lyrics, synced: found.isSynced, choosing: $choosing)
                        .opacity(hovering ? 1 : 0.35)
                }
                .transition(.opacity)
            } else {
                Color.clear
            }
        }
        .animation(.easeInOut(duration: 0.2), value: choosing)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onAppear { lyrics.watch() }
        .onDisappear { lyrics.unwatch() }
        // Another song, another set of lyrics to choose from.
        .onChange(of: media.nowPlaying.trackKey) { choosing = false }
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
                        LyricLineView(line: line, karaoke: distance(index) == 0 ? found.karaoke(at: index) : nil,
                                      distance: distance(index), size: fontSize, playing: media.nowPlaying.isPlaying,
                                      position: { lyrics.position(at: $0) })
                            .id(index)
                            .onTapGesture { media.seek(to: max(0, line.time)) }
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
    let karaoke: KaraokeLine?
    let distance: Int
    let size: CGFloat
    let playing: Bool
    let position: (Date) -> TimeInterval

    var body: some View {
        Group {
            if line.isPause {
                BreathingDots(active: distance == 0 && playing, size: size)
            } else if let karaoke, distance == 0 {
                SungLine(line: line, karaoke: karaoke, size: size, unlit: .white.opacity(0.42), moving: playing, position: position)
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
        PulsingDots(color: .white, dot: size * 0.42, spacing: size * 0.35, motion: .swell, active: active)
            .frame(height: size * 1.2)
    }
}

/// The lyrics' menu: their timing, other lyrics, or none for this song.
private struct LyricsMenu: View {
    let lyrics: LyricsModel
    let synced: Bool
    @Binding var choosing: Bool

    var body: some View {
        Menu {
            if synced {
                Section {
                    Button { lyrics.nudge(by: -1) } label: {
                        Label { Text("Show Lyrics 0.5 s Sooner", bundle: .module) } icon: { Image(systemName: "minus.circle") }
                    }
                    Button { lyrics.nudge(by: 1) } label: {
                        Label { Text("Show Lyrics 0.5 s Later", bundle: .module) } icon: { Image(systemName: "plus.circle") }
                    }
                    if lyrics.offset != 0 {
                        Button { lyrics.resetOffset() } label: {
                            Label { Text("Reset Timing", bundle: .module) } icon: { Image(systemName: "arrow.counterclockwise") }
                        }
                    }
                } header: {
                    if lyrics.offset == 0 {
                        Text("Timing", bundle: .module)
                    } else {
                        Text("Timing: \(LyricsTiming.format(lyrics.offset))", bundle: .module)
                    }
                }
            }
            Section {
                Button { choosing = true } label: {
                    Label { Text("Not the Right Lyrics?", bundle: .module) } icon: { Image(systemName: "text.magnifyingglass") }
                }
                if lyrics.hasChoice {
                    Button { lyrics.choose(nil) } label: {
                        Label { Text("Use the Lyrics Found First", bundle: .module) } icon: { Image(systemName: "arrow.uturn.backward") }
                    }
                }
                Button { lyrics.hideForTrack() } label: {
                    Label { Text("Hide Lyrics for This Song", bundle: .module) } icon: { Image(systemName: "eye.slash") }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("Lyrics", bundle: .module))
    }
}

enum LyricsTiming {
    /// "+1.5 s", "−0.5 s".
    static func format(_ offset: TimeInterval) -> String {
        let number = abs(offset).formatted(.number.precision(.fractionLength(1)))
        return (offset < 0 ? "−" : "+") + number + " s"
    }
}

/// Every recording LRCLIB has for the song, to choose the right lyrics: asked only when this opens, with the same
/// title and artist as the lookup.
private struct LyricsChooser: View {
    let lyrics: LyricsModel
    let done: () -> Void
    @State private var records: [LyricsRecord]?
    @State private var loading = true

    var body: some View {
        LyricsChooserList(lyrics: lyrics, records: records, loading: loading, done: done)
            .task {
                records = await lyrics.candidates()
                loading = false
            }
    }
}

/// The recordings to choose from, the one chosen ticked.
struct LyricsChooserList: View {
    let lyrics: LyricsModel
    let records: [LyricsRecord]?
    let loading: Bool
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Choose the Lyrics", bundle: .module)
                    .font(Theme.Font.title)
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Button(action: done) { Text("Cancel", bundle: .module) }
                    .buttonStyle(.plain)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.secondaryText)
            }
            if loading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let records, !records.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(records) { record in
                            ChoiceRow(record: record, chosen: record.id == lyrics.query.flatMap(lyrics.overrides.choice(for:))) {
                                lyrics.choose(record)
                                done()
                            }
                        }
                    }
                }
            } else {
                Text(records == nil ? "LRCLIB cannot be reached. Try again in a moment." : "LRCLIB has no other lyrics for this song.", bundle: .module)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct ChoiceRow: View {
    let record: LyricsRecord
    let chosen: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: record.trackName)
                        .font(Theme.Font.body)
                        .foregroundStyle(.white)
                    Text(verbatim: details)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .lineLimit(1)
                Spacer(minLength: 6)
                if chosen {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous).fill(.white.opacity(hovering ? 0.1 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    /// What tells two recordings apart, the most telling first: "Synced · 4:03 · Hurry Up · M83".
    private var details: String {
        var parts = [record.hasSyncedLyrics
            ? String(localized: "Synced", bundle: .module)
            : record.hasPlainLyrics ? String(localized: "Not synced", bundle: .module) : String(localized: "Instrumental", bundle: .module)]
        if let duration = record.duration, duration > 0 { parts.append(PlaybackScrubber.format(duration)) }
        if let album = record.albumName, !album.isEmpty { parts.append(album) }
        if !record.artistName.isEmpty { parts.append(record.artistName) }
        return parts.joined(separator: " · ")
    }
}
