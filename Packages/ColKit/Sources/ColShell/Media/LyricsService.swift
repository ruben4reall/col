import CryptoKit
import Foundation
import ColCore

/// Finds the lyrics of a track: a `.lrc` file of the user's first, then LRCLIB, an open database of lyrics that needs
/// no account. Only the title, the artist, the album and the length of the track are sent. Answers are kept on disk,
/// misses for a week, so a track is looked up once.
actor LyricsService {
    static let shared = LyricsService()

    enum Answer: Sendable, Equatable {
        case found(Lyrics)
        case instrumental
        case notFound
        /// The database could not be reached, or asked to wait: try again later.
        case unavailable
    }

    private let session: URLSession
    private var memory: [String: Answer] = [:]
    /// LRCLIB asks clients to slow down with a 429 and a Retry-After: nothing is asked before this moment.
    private var quietUntil: Date?

    private static let base = URL(string: "https://lrclib.net/api")!
    private static let missLifetime: TimeInterval = 7 * 24 * 3600

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        session = URLSession(configuration: configuration)
    }

    /// LRCLIB asks every client to say who it is.
    static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return "Col \(version) (https://github.com/ruben4reall/col)"
    }

    /// The folder where `.lrc` files of the user's own take precedence: `Artist - Title.lrc`.
    static var userFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Col/Lyrics", isDirectory: true)
    }

    func lyrics(for query: LyricsQuery) async -> Answer {
        if let local = Self.userLyrics(for: query) { return .found(local) }
        let key = query.cacheKey
        if let answer = memory[key] { return answer }
        if let answer = Self.cached(key) {
            memory[key] = answer
            return answer
        }
        if let quietUntil, quietUntil > Date() { return .unavailable }
        let (answer, record) = await fetch(query)
        // `-ColDebug YES` tells what each lookup found.
        if UserDefaults.standard.bool(forKey: "ColDebug") {
            let summary = switch answer {
            case .found(let lyrics): "\(lyrics.lines.count) lines, \(lyrics.isSynced ? "synced" : "plain")"
            case .instrumental: "instrumental"
            case .notFound: "not found"
            case .unavailable: "unavailable"
            }
            FileHandle.standardError.write(Data("lyrics: \(query.mainArtist) - \(query.cleanTitle): \(summary)\n".utf8))
        }
        if answer != .unavailable {
            memory[key] = answer
            Self.store(record, for: key)
        }
        return answer
    }

    // MARK: LRCLIB

    private struct Record: Decodable {
        var duration: Double?
        var instrumental: Bool?
        var plainLyrics: String?
        var syncedLyrics: String?
    }

    /// The answer, and the record it came from, kept as it was for the cache.
    private func fetch(_ query: LyricsQuery) async -> (Answer, Record?) {
        // The exact track first, then a search that tolerates a different album or spelling.
        var exact = URLComponents(url: Self.base.appendingPathComponent("get"), resolvingAgainstBaseURL: false)!
        exact.queryItems = [
            URLQueryItem(name: "track_name", value: query.cleanTitle),
            URLQueryItem(name: "artist_name", value: query.mainArtist),
        ] + (query.album.isEmpty ? [] : [URLQueryItem(name: "album_name", value: query.album)])
          + (query.duration > 0 ? [URLQueryItem(name: "duration", value: String(Int(query.duration.rounded())))] : [])
        switch await request(exact.url!, as: Record.self) {
        case .success(let record?): return (answer(from: record), record)
        case .failure: return (.unavailable, nil)
        case .success(nil): break
        }
        var search = URLComponents(url: Self.base.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        search.queryItems = [URLQueryItem(name: "track_name", value: query.cleanTitle), URLQueryItem(name: "artist_name", value: query.mainArtist)]
        switch await request(search.url!, as: [Record].self) {
        case .success(let records?):
            let candidates = records.filter { query.matches(duration: $0.duration) }
            // Synced lyrics beat plain ones.
            if let best = candidates.first(where: { $0.syncedLyrics?.isEmpty == false }) ?? candidates.first { return (answer(from: best), best) }
            return (.notFound, nil)
        case .success(nil): return (.notFound, nil)
        case .failure: return (.unavailable, nil)
        }
    }

    private func answer(from record: Record) -> Answer {
        if record.instrumental == true { return .instrumental }
        if let synced = record.syncedLyrics, let lyrics = Lyrics.parse(lrc: synced) { return .found(lyrics) }
        if let plain = record.plainLyrics, let lyrics = Lyrics.plain(plain) { return .found(lyrics) }
        return .notFound
    }

    private struct Unreachable: Error {}

    /// Nil for a 404, a failure for anything that should be tried again later.
    private func request<T: Decodable>(_ url: URL, as type: T.Type) async -> Result<T?, Unreachable> {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return .failure(Unreachable()) }
            switch http.statusCode {
            case 200: return .success(try? JSONDecoder().decode(T.self, from: data))
            case 404: return .success(nil)
            case 429:
                let wait = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(Double.init) ?? 60
                quietUntil = Date().addingTimeInterval(min(max(wait, 5), 3600))
                return .failure(Unreachable())
            default: return .failure(Unreachable())
            }
        } catch {
            return .failure(Unreachable())
        }
    }

    // MARK: The user's own files

    static func userLyrics(for query: LyricsQuery) -> Lyrics? {
        let folder = userFolder
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return nil }
        let wanted = "\(query.mainArtist) - \(query.cleanTitle)".lowercased()
        guard let file = files.first(where: { $0.pathExtension.lowercased() == "lrc" && $0.deletingPathExtension().lastPathComponent.lowercased() == wanted }),
              let text = try? String(contentsOf: file, encoding: .utf8)
        else { return nil }
        return Lyrics.parse(lrc: text) ?? Lyrics.plain(text)
    }

    // MARK: The cache

    private struct Entry: Codable {
        var synced: String?
        var plain: String?
        var instrumental: Bool
        var fetched: Date
    }

    private static var cacheFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Col/Lyrics", isDirectory: true)
    }

    private static func file(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheFolder.appendingPathComponent(digest + ".json")
    }

    private static func cached(_ key: String) -> Answer? {
        guard let data = try? Data(contentsOf: file(for: key)), let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        if entry.instrumental { return .instrumental }
        if let synced = entry.synced, let lyrics = Lyrics.parse(lrc: synced) { return .found(lyrics) }
        if let plain = entry.plain, let lyrics = Lyrics.plain(plain) { return .found(lyrics) }
        // A miss is asked again after a week: someone may have added the lyrics since.
        return Date().timeIntervalSince(entry.fetched) < missLifetime ? .notFound : nil
    }

    /// Keeps a record as LRCLIB gave it, or a miss when there is none.
    private static func store(_ record: Record?, for key: String) {
        let entry = Entry(synced: record?.syncedLyrics, plain: record?.plainLyrics, instrumental: record?.instrumental == true, fetched: Date())
        try? FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(entry).write(to: file(for: key), options: .atomic)
    }
}
