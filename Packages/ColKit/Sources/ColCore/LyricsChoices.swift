import Foundation

/// What the user changed about one track's lyrics: their timing, the lyrics chosen among those LRCLIB has, or that
/// they are hidden.
public struct TrackLyricsSettings: Codable, Equatable, Sendable {
    /// Seconds the lyrics show later (sooner when negative), in steps of half a second.
    public var offset: TimeInterval = 0
    public var hidden = false
    /// The LRCLIB record chosen for this track, in place of the one found.
    public var choice: Int?
    /// The track, to list it in the settings.
    public var title: String
    public var artist: String
    /// When it was last changed, so the oldest settings go first when there are too many.
    public var changed: Date

    public init(title: String, artist: String, changed: Date = Date()) {
        self.title = title
        self.artist = artist
        self.changed = changed
    }

    /// Nothing changed: there is nothing to keep.
    public var isDefault: Bool { offset == 0 && !hidden && choice == nil }
}

/// The user's changes to the lyrics of the tracks they play, by track.
public struct LyricsOverrides: Codable, Equatable, Sendable {
    public private(set) var tracks: [String: TrackLyricsSettings] = [:]

    /// One press moves the lyrics by half a second.
    public static let step: TimeInterval = 0.5
    /// Lyrics a minute off are other lyrics: half a minute either way at most.
    public static let limit: TimeInterval = 30
    /// The most tracks remembered; the oldest changes are forgotten first.
    public static let capacity = 500

    public init() {}

    public func settings(for query: LyricsQuery) -> TrackLyricsSettings? {
        tracks[query.cacheKey]
    }

    public func offset(for query: LyricsQuery) -> TimeInterval {
        tracks[query.cacheKey]?.offset ?? 0
    }

    public func isHidden(_ query: LyricsQuery) -> Bool {
        tracks[query.cacheKey]?.hidden ?? false
    }

    public func choice(for query: LyricsQuery) -> Int? {
        tracks[query.cacheKey]?.choice
    }

    /// Moves the lyrics by steps of half a second: positive shows them later, negative sooner.
    public mutating func nudge(_ query: LyricsQuery, by steps: Int, now: Date = Date()) {
        change(query, now: now) { settings in
            let moved = settings.offset + Double(steps) * Self.step
            settings.offset = min(max((moved / Self.step).rounded() * Self.step, -Self.limit), Self.limit)
        }
    }

    public mutating func resetOffset(_ query: LyricsQuery, now: Date = Date()) {
        change(query, now: now) { $0.offset = 0 }
    }

    public mutating func setHidden(_ hidden: Bool, for query: LyricsQuery, now: Date = Date()) {
        change(query, now: now) { $0.hidden = hidden }
    }

    /// Chooses an LRCLIB record for the track, or goes back to the one found with nil. A new choice starts on time.
    public mutating func choose(_ id: Int?, for query: LyricsQuery, now: Date = Date()) {
        change(query, now: now) { settings in
            if settings.choice != id { settings.offset = 0 }
            settings.choice = id
        }
    }

    /// Shows the lyrics of a track again, from the list of hidden ones.
    public mutating func unhide(key: String) {
        guard var settings = tracks[key] else { return }
        settings.hidden = false
        tracks[key] = settings.isDefault ? nil : settings
    }

    /// The tracks whose lyrics are hidden, most recent first.
    public var hiddenTracks: [(key: String, settings: TrackLyricsSettings)] {
        tracks.filter { $0.value.hidden }
            .map { (key: $0.key, settings: $0.value) }
            .sorted { $0.settings.changed > $1.settings.changed }
    }

    private mutating func change(_ query: LyricsQuery, now: Date, _ edit: (inout TrackLyricsSettings) -> Void) {
        let key = query.cacheKey
        var settings = tracks[key] ?? TrackLyricsSettings(title: query.cleanTitle, artist: query.mainArtist, changed: now)
        edit(&settings)
        settings.changed = now
        tracks[key] = settings.isDefault ? nil : settings
        if tracks.count > Self.capacity, let oldest = tracks.min(by: { $0.value.changed < $1.value.changed })?.key {
            tracks[oldest] = nil
        }
    }
}

/// A record of LRCLIB: the lyrics of one recording of a track, as its search and get answers give them.
public struct LyricsRecord: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var trackName: String
    public var artistName: String
    public var albumName: String?
    public var duration: Double?
    public var instrumental: Bool?
    public var plainLyrics: String?
    public var syncedLyrics: String?

    public init(id: Int, trackName: String, artistName: String, albumName: String? = nil, duration: Double? = nil,
                instrumental: Bool? = nil, plainLyrics: String? = nil, syncedLyrics: String? = nil) {
        self.id = id
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.duration = duration
        self.instrumental = instrumental
        self.plainLyrics = plainLyrics
        self.syncedLyrics = syncedLyrics
    }

    private enum CodingKeys: String, CodingKey {
        case id, trackName, artistName, albumName, duration, instrumental, plainLyrics, syncedLyrics
    }

    /// Lenient: a record missing a name still decodes, so one odd entry does not hide a whole list.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? values.decodeIfPresent(Int.self, forKey: .id)) ?? 0
        trackName = (try? values.decodeIfPresent(String.self, forKey: .trackName)) ?? ""
        artistName = (try? values.decodeIfPresent(String.self, forKey: .artistName)) ?? ""
        albumName = try? values.decodeIfPresent(String.self, forKey: .albumName)
        duration = try? values.decodeIfPresent(Double.self, forKey: .duration)
        instrumental = try? values.decodeIfPresent(Bool.self, forKey: .instrumental)
        plainLyrics = try? values.decodeIfPresent(String.self, forKey: .plainLyrics)
        syncedLyrics = try? values.decodeIfPresent(String.self, forKey: .syncedLyrics)
    }

    public var hasSyncedLyrics: Bool { syncedLyrics?.isEmpty == false }
    public var hasPlainLyrics: Bool { plainLyrics?.isEmpty == false }
    public var isInstrumental: Bool { instrumental == true }

    /// The lyrics the record holds: synced ones first, else plain ones.
    public var lyrics: Lyrics? {
        if let synced = syncedLyrics, let lyrics = Lyrics.parse(lrc: synced) { return lyrics }
        if let plain = plainLyrics { return Lyrics.plain(plain) }
        return nil
    }

    /// The records a search found, best first, for the user to choose from: those with lyrics, synced before plain,
    /// the length closest to the track's first, at most `limit`.
    public static func ranked(_ records: [LyricsRecord], for query: LyricsQuery, limit: Int = 12) -> [LyricsRecord] {
        let useful = records.filter { $0.id > 0 && ($0.hasSyncedLyrics || $0.hasPlainLyrics || $0.isInstrumental) }
        func gap(_ record: LyricsRecord) -> Double {
            guard query.duration > 0, let duration = record.duration else { return .greatestFiniteMagnitude }
            return abs(duration - query.duration)
        }
        func rank(_ record: LyricsRecord) -> Int {
            if record.hasSyncedLyrics { return 0 }
            if record.hasPlainLyrics { return 1 }
            return 2
        }
        var seen = Set<Int>()
        return useful
            .filter { seen.insert($0.id).inserted }
            .enumerated()
            .sorted { a, b in
                // Same length within two seconds counts as the same: the database's order decides then.
                let close = (query.matches(duration: a.element.duration), query.matches(duration: b.element.duration))
                if close.0 != close.1 { return close.0 }
                if rank(a.element) != rank(b.element) { return rank(a.element) < rank(b.element) }
                if !close.0, gap(a.element) != gap(b.element) { return gap(a.element) < gap(b.element) }
                return a.offset < b.offset
            }
            .prefix(limit)
            .map(\.element)
    }
}
