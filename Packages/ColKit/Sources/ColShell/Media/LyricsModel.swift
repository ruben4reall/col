import Foundation
import ColCore
import Observation

/// The lyrics of what plays, and the line being sung. Lyrics are looked up once per track; the line is followed by a
/// timer that wakes exactly when the next line starts, and only while lyrics are on screen and the music plays.
///
/// What the user changed about a track's lyrics (their timing, other lyrics chosen, hidden) applies here, so every
/// place that shows them, the island, its wing, the Lock Screen and the desktop, shows the same.
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
        /// The user hid the lyrics of this track.
        case hidden
    }

    private(set) var state: State = .idle
    /// The line being sung, in the lyrics' lines; nil before the first one, and for plain lyrics.
    private(set) var current: Int?
    /// The track whose lyrics these are.
    private(set) var query: LyricsQuery?
    /// The user's changes, by track.
    private(set) var overrides = LyricsOverridesStore.load()

    /// Called when the line on show changes, for the closed island's wing.
    @ObservationIgnored var onLineChange: (() -> Void)?

    @ObservationIgnored private var playing = NowPlaying()
    @ObservationIgnored private var watchers = 0
    @ObservationIgnored private var tick: Task<Void, Never>?
    @ObservationIgnored private var lookup: Task<Void, Never>?
    /// Lookups that found the database unreachable, for the track playing: a few more tries, further apart.
    @ObservationIgnored private var retries = 0
    /// The lyrics as found, before the user's timing moves them.
    @ObservationIgnored private var found: Lyrics?
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: LyricsOverridesStore.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.overridesChanged() }
        }
    }

    var lyrics: Lyrics? {
        if case .found(let lyrics) = state { return lyrics }
        return nil
    }

    /// The text of the line being sung, for the wing: nil in a pause, before the first line, or without lyrics.
    var currentLine: String? {
        guard let lyrics, let current, lyrics.lines.indices.contains(current), !lyrics.lines[current].isPause else { return nil }
        return lyrics.lines[current].text
    }

    /// Seconds the lyrics of the track show later (sooner when negative).
    var offset: TimeInterval { query.map(overrides.offset(for:)) ?? 0 }

    /// True when the user chose these lyrics among LRCLIB's.
    var hasChoice: Bool { query.flatMap(overrides.choice(for:)) != nil }

    /// Where the song is now, for views that fill the words as they are sung.
    func position(at date: Date) -> TimeInterval { playing.position(at: date) }

    var isPlaying: Bool { playing.isPlaying }

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

    /// Shows sample lyrics as if found for what plays, at a moment of the song, for screenshots: nothing is looked up.
    func showDemo(_ lyrics: Lyrics, playing nowPlaying: NowPlaying) {
        lookup?.cancel()
        playing = nowPlaying
        query = LyricsQuery(title: nowPlaying.title, artist: nowPlaying.artist, album: nowPlaying.album, duration: nowPlaying.duration)
        setFound(lyrics)
        current = self.lyrics?.index(at: nowPlaying.position(at: Date()))
    }

    // MARK: The user's changes

    /// Shows the lyrics of this track half a second later per step (sooner for negative steps).
    func nudge(by steps: Int) {
        guard let query else { return }
        save { $0.nudge(query, by: steps) }
    }

    func resetOffset() {
        guard let query else { return }
        save { $0.resetOffset(query) }
    }

    /// Hides the lyrics of this track everywhere, until shown again from the settings.
    func hideForTrack() {
        guard let query else { return }
        save { $0.setHidden(true, for: query) }
    }

    /// Chooses other lyrics for this track among LRCLIB's, or goes back to the ones found with nil.
    func choose(_ record: LyricsRecord?) {
        guard let query else { return }
        guard let record else {
            save { $0.choose(nil, for: query) }
            return
        }
        // Shown at once: no need to ask LRCLIB again for lyrics already in hand.
        Task { await LyricsService.shared.remember(record) }
        lookup?.cancel()
        shownChoice = record.id
        found = record.lyrics
        save { $0.choose(record.id, for: query) }
        if found == nil { setState(record.isInstrumental ? .instrumental : .notFound) }
    }

    /// Every recording LRCLIB has for this track, best first; nil when it cannot be reached.
    func candidates() async -> [LyricsRecord]? {
        guard let query else { return [] }
        return await LyricsService.shared.candidates(for: query)
    }

    private func save(_ change: (inout LyricsOverrides) -> Void) {
        var overrides = self.overrides
        change(&overrides)
        LyricsOverridesStore.save(overrides)
    }

    /// The overrides changed, here or in the settings: the track playing follows them.
    private func overridesChanged() {
        let previous = overrides
        overrides = LyricsOverridesStore.load()
        guard let query else { return }
        let before = previous.settings(for: query), after = overrides.settings(for: query)
        guard before != after else { return }
        if after?.hidden == true {
            lookup?.cancel()
            setState(.hidden)
        } else if state == .hidden || after?.choice != shownChoice {
            // Shown again, or other lyrics chosen elsewhere: looked up again.
            find(query)
        } else if let found {
            // Only the timing changed.
            setFound(found)
            follow()
        }
    }

    /// The LRCLIB record the lyrics on show come from, when the user chose it.
    @ObservationIgnored private var shownChoice: Int?

    // MARK: Lookup

    private func find(_ query: LyricsQuery) {
        lookup?.cancel()
        if overrides.isHidden(query) {
            setState(.hidden)
            return
        }
        setState(.loading)
        let choice = overrides.choice(for: query)
        lookup = Task { @MainActor [weak self] in
            let answer = if let choice {
                await LyricsService.shared.lyrics(choice: choice)
            } else {
                await LyricsService.shared.lyrics(for: query)
            }
            guard let self, !Task.isCancelled, self.query == query else { return }
            self.shownChoice = choice
            switch answer {
            case .found(let lyrics): self.setFound(lyrics)
            case .instrumental: self.setState(.instrumental)
            case .notFound: self.setState(.notFound)
            case .unavailable:
                self.setState(.unavailable)
                self.retryLater(query)
            }
            self.follow()
        }
    }

    /// Lyrics found: shown with the track's timing.
    private func setFound(_ lyrics: Lyrics) {
        found = lyrics
        shownChoice = query.flatMap(overrides.choice(for:))
        setState(.found(lyrics.shifted(by: offset)))
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
        if case .found = state {} else { found = nil }
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
        guard watchers > 0, playing.isPlaying, let delay = lyrics.wait(after: position, rate: playing.rate) else { return }
        tick = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.follow()
        }
    }
}

/// The user's changes to the lyrics of their tracks, kept in the settings. Only titles, artists and LRCLIB's record
/// numbers: never the lyrics themselves.
@MainActor
enum LyricsOverridesStore {
    static let didChange = Notification.Name("ColLyricsOverridesDidChange")
    private static let key = "lyricsOverrides"

    static func load() -> LyricsOverrides {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(LyricsOverrides.self, from: $0) } ?? LyricsOverrides()
    }

    static func save(_ overrides: LyricsOverrides) {
        if overrides.tracks.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(try? JSONEncoder().encode(overrides), forKey: key)
        }
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
