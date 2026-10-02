import Foundation
import ColCore
import Observation

/// The lyrics of what plays, and the line being sung. Lyrics are looked up once per track; the line is followed by a
/// timer that wakes exactly when the next line starts, and only while lyrics are on screen and the music plays.
@MainActor
@Observable
final class LyricsModel {
    enum State: Equatable {
        /// Lyrics are turned off in the settings.
        case off
        /// Nothing plays.
        case idle
        case loading
        case found(Lyrics)
        case instrumental
        case notFound
        /// The database could not be reached; the next track tries again.
        case unavailable
    }

    private(set) var state: State = .idle
    /// The line being sung, in the lyrics' lines; nil before the first one, and for plain lyrics.
    private(set) var current: Int?

    /// Called when the line on show changes, for the closed island's wing.
    @ObservationIgnored var onLineChange: (() -> Void)?

    @ObservationIgnored private var query: LyricsQuery?
    @ObservationIgnored private var playing = NowPlaying()
    @ObservationIgnored private var watchers = 0
    @ObservationIgnored private var tick: Task<Void, Never>?
    @ObservationIgnored private var lookup: Task<Void, Never>?
    /// Lookups that found the database unreachable, for the track playing: a few more tries, further apart.
    @ObservationIgnored private var retries = 0

    var lyrics: Lyrics? {
        if case .found(let lyrics) = state { return lyrics }
        return nil
    }

    /// The text of the line being sung, for the wing: nil in a pause, before the first line, or without lyrics.
    var currentLine: String? {
        guard let lyrics, let current, lyrics.lines.indices.contains(current), !lyrics.lines[current].isPause else { return nil }
        return lyrics.lines[current].text
    }

    /// The player changed: a new track is looked up, a seek or a pause moves the line.
    func update(_ nowPlaying: NowPlaying) {
        playing = nowPlaying
        guard Preferences.showsLyrics else {
            setState(.off)
            return
        }
        guard !nowPlaying.isEmpty, !nowPlaying.title.isEmpty else {
            query = nil
            setState(.idle)
            return
        }
        let next = LyricsQuery(title: nowPlaying.title, artist: nowPlaying.artist, album: nowPlaying.album, duration: nowPlaying.duration)
        if next.cacheKey != query?.cacheKey || state == .off || state == .idle {
            query = next
            retries = 0
            find(next)
        }
        follow()
    }

    /// Views that show the lyrics, and the wing, say when they appear and go: the line is only followed while one does.
    func watch() {
        watchers += 1
        follow()
    }

    func unwatch() {
        watchers = max(0, watchers - 1)
        follow()
    }

    private func find(_ query: LyricsQuery) {
        lookup?.cancel()
        setState(.loading)
        lookup = Task { @MainActor [weak self] in
            let answer = await LyricsService.shared.lyrics(for: query)
            guard let self, !Task.isCancelled, self.query == query else { return }
            switch answer {
            case .found(let lyrics): self.setState(.found(lyrics))
            case .instrumental: self.setState(.instrumental)
            case .notFound: self.setState(.notFound)
            case .unavailable:
                self.setState(.unavailable)
                self.retryLater(query)
            }
            self.follow()
        }
    }

    /// The database was down or busy: ask again in a moment, twice at most for the same track.
    private func retryLater(_ query: LyricsQuery) {
        guard retries < 2 else { return }
        retries += 1
        let delay: Duration = retries == 1 ? .seconds(6) : .seconds(30)
        lookup = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, self.query == query, self.state == .unavailable else { return }
            self.find(query)
        }
    }

    private func setState(_ state: State) {
        guard state != self.state else { return }
        self.state = state
        current = nil
        tick?.cancel()
        onLineChange?()
    }

    /// Moves to the line sung now and sleeps until the next one starts.
    private func follow() {
        tick?.cancel()
        guard let lyrics, lyrics.isSynced else { return }
        let position = playing.position(at: Date())
        let index = lyrics.index(at: position)
        if index != current {
            current = index
            onLineChange?()
        }
        guard watchers > 0, playing.isPlaying, let next = lyrics.nextChange(after: position) else { return }
        let rate = max(playing.rate, 0.1)
        // A little early, so the line arrives with the voice rather than after it.
        let delay = max(0.05, (next - position) / rate - 0.12)
        tick = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.follow()
        }
    }
}
