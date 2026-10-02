import Foundation

/// One line from the media bridge, as written by ColMediaBridge.
public struct NowPlayingUpdate: Decodable, Sendable, Equatable {
    public var idle: Bool?
    public var playing: Bool?
    public var title: String?
    public var artist: String?
    public var album: String?
    public var duration: Double?
    public var elapsed: Double?
    public var timestamp: Double?
    public var rate: Double?
    public var pid: Int32?
    /// Base64 image data; an empty string means the artwork is gone; absent means unchanged.
    public var artwork: String?

    public init(from line: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: line)
    }

    private enum CodingKeys: String, CodingKey {
        case idle, playing, title, artist, album, duration, elapsed, timestamp, rate, pid, artwork
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        idle = try values.decodeIfPresent(Bool.self, forKey: .idle)
        // The bridge writes booleans as 0 and 1.
        if let flag = try? values.decodeIfPresent(Bool.self, forKey: .playing) {
            playing = flag
        } else if let number = try? values.decodeIfPresent(Int.self, forKey: .playing) {
            playing = number != 0
        }
        title = try values.decodeIfPresent(String.self, forKey: .title)
        artist = try values.decodeIfPresent(String.self, forKey: .artist)
        album = try values.decodeIfPresent(String.self, forKey: .album)
        duration = try values.decodeIfPresent(Double.self, forKey: .duration)
        elapsed = try values.decodeIfPresent(Double.self, forKey: .elapsed)
        timestamp = try values.decodeIfPresent(Double.self, forKey: .timestamp)
        rate = try values.decodeIfPresent(Double.self, forKey: .rate)
        pid = try values.decodeIfPresent(Int32.self, forKey: .pid)
        artwork = try values.decodeIfPresent(String.self, forKey: .artwork)
    }
}

/// What is playing, kept up to date from the bridge's partial updates.
public struct NowPlaying: Equatable, Sendable {
    public var isPlaying = false
    public var title = ""
    public var artist = ""
    public var album = ""
    public var duration: Double = 0
    /// Position at `timestamp`; the position now is extrapolated with the rate.
    public var elapsed: Double = 0
    public var timestamp = Date.distantPast
    public var rate: Double = 0
    public var pid: Int32 = 0

    public init() {}

    /// Nothing has been reported, or the player went away.
    public var isEmpty: Bool { title.isEmpty && artist.isEmpty && pid == 0 }

    /// Identity of the track, to notice when a new one starts.
    public var trackKey: String { "\(title)\n\(artist)\n\(album)" }

    public enum ArtworkChange: Equatable, Sendable {
        case unchanged
        case removed
        case replaced(Data)
    }

    /// Applies a bridge line and says what happened to the artwork.
    public mutating func apply(_ update: NowPlayingUpdate) -> ArtworkChange {
        if update.idle == true {
            self = NowPlaying()
            return .removed
        }
        isPlaying = update.playing ?? isPlaying
        title = update.title ?? ""
        artist = update.artist ?? ""
        album = update.album ?? ""
        duration = max(0, update.duration ?? 0)
        elapsed = max(0, update.elapsed ?? 0)
        rate = update.rate ?? (isPlaying ? 1 : 0)
        timestamp = update.timestamp.map(Date.init(timeIntervalSince1970:)) ?? Date()
        pid = update.pid ?? pid
        switch update.artwork {
        case nil: return .unchanged
        case "": return .removed
        case let encoded?: return Data(base64Encoded: encoded).map(ArtworkChange.replaced) ?? .unchanged
        }
    }

    /// Playback position at `date`, clamped to the track.
    public func position(at date: Date) -> Double {
        let moving = isPlaying ? max(rate, 0) : 0
        let position = elapsed + date.timeIntervalSince(timestamp) * moving
        return duration > 0 ? min(max(position, 0), duration) : max(position, 0)
    }
}

extension NowPlaying {
    /// Plays or pauses at once, keeping the position continuous, before the player confirms.
    public mutating func setPlaying(_ playing: Bool, at date: Date) {
        elapsed = position(at: date)
        timestamp = date
        isPlaying = playing
        rate = playing ? 1 : 0
    }

    public mutating func seek(to position: Double, at date: Date) {
        elapsed = duration > 0 ? min(max(position, 0), duration) : max(position, 0)
        timestamp = date
    }
}
