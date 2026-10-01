import Foundation

/// Recent copies, newest first, text or images. Kept in memory only, except the entries the user pins.
public struct ClipboardHistory: Sendable, Equatable {
    public struct Entry: Sendable, Equatable, Identifiable {
        public var id: UUID
        public var text: String
        /// PNG data of an image copy; nil for text.
        public var image: Data?
        public var copied: Date
        public var sourceApp: String?
        public var pinned: Bool

        public init(id: UUID = UUID(), text: String, image: Data? = nil, copied: Date, sourceApp: String? = nil, pinned: Bool = false) {
            self.id = id
            self.text = text
            self.image = image
            self.copied = copied
            self.sourceApp = sourceApp
            self.pinned = pinned
        }

        public var isImage: Bool { image != nil }
    }

    public private(set) var entries: [Entry] = []
    /// Unpinned entries kept; pinned ones never count against it.
    public var capacity: Int

    public init(capacity: Int = 24) {
        self.capacity = capacity
    }

    /// Pinned entries first, then the rest, newest first.
    public var ordered: [Entry] {
        entries.filter(\.pinned) + entries.filter { !$0.pinned }
    }

    /// Adds a text copy. Blank text is ignored; copying something again moves it to the top instead of repeating it.
    public mutating func add(_ text: String, at date: Date, from app: String? = nil) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let stored = text.count > 20_000 ? String(text.prefix(20_000)) : text
        let wasPinned = entries.first { $0.image == nil && $0.text == stored }?.pinned ?? false
        entries.removeAll { $0.image == nil && $0.text == stored }
        entries.insert(Entry(text: stored, copied: date, sourceApp: app, pinned: wasPinned), at: 0)
        trim()
    }

    /// Adds an image copy, described by `label` (such as its size).
    public mutating func add(image: Data, label: String, at date: Date, from app: String? = nil) {
        entries.removeAll { $0.image == image && !$0.pinned }
        entries.insert(Entry(text: label, image: image, copied: date, sourceApp: app), at: 0)
        trim()
    }

    public mutating func togglePin(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].pinned.toggle()
        trim()
    }

    /// Restores pinned text saved from a previous launch.
    public mutating func restorePinned(_ texts: [String]) {
        for text in texts where !entries.contains(where: { $0.pinned && $0.text == text }) {
            entries.append(Entry(text: text, copied: .distantPast, pinned: true))
        }
    }

    public var pinnedTexts: [String] {
        entries.filter { $0.pinned && $0.image == nil }.map(\.text)
    }

    public mutating func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// Forgets everything but the pins.
    public mutating func clear() {
        entries.removeAll { !$0.pinned }
    }

    private mutating func trim() {
        var unpinned = 0
        entries = entries.filter { entry in
            if entry.pinned { return true }
            unpinned += 1
            return unpinned <= capacity
        }
    }
}

/// A countdown that knows where it is at any moment without ticking.
public struct Countdown: Sendable, Equatable {
    public var total: TimeInterval
    public var ends: Date?
    /// Set while paused: what was left when it stopped.
    public var pausedRemaining: TimeInterval?

    public init(total: TimeInterval, starting date: Date) {
        self.total = max(total, 1)
        ends = date.addingTimeInterval(self.total)
    }

    public func remaining(at date: Date) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let ends else { return 0 }
        return max(ends.timeIntervalSince(date), 0)
    }

    /// 1 when it starts, 0 when it rings.
    public func fraction(at date: Date) -> Double {
        remaining(at: date) / total
    }

    public var isPaused: Bool { pausedRemaining != nil }

    public func isFinished(at date: Date) -> Bool {
        !isPaused && remaining(at: date) <= 0
    }

    public mutating func pause(at date: Date) {
        guard !isPaused else { return }
        pausedRemaining = remaining(at: date)
        ends = nil
    }

    public mutating func resume(at date: Date) {
        guard let left = pausedRemaining else { return }
        ends = date.addingTimeInterval(left)
        pausedRemaining = nil
    }

    /// "4:05", or "1:02:03" past an hour; rounds up so it reads 0:00 only when it rings.
    public static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let hours = total / 3600, minutes = total / 60 % 60, rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}

public enum MeetingLink {
    private static let hosts = ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "whereby.com", "meet.jit.si", "webex.com", "facetime.apple.com"]

    /// The first video call link in an event's URL, location or notes.
    public static func find(in texts: [String?]) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for text in texts.compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector?.matches(in: text, range: range) ?? [] {
                guard let url = match.url, let host = url.host?.lowercased() else { continue }
                if hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url }
            }
        }
        return nil
    }
}

/// How often to look at the pasteboard, which has no change notification. Copying takes a keystroke or a click, so
/// while nobody touches the Mac the checks can space out; the island also checks as it opens and when you switch
/// apps, so the history is never stale when you look.
public enum ClipboardPolling {
    public static func interval(secondsSinceInput idle: TimeInterval) -> TimeInterval {
        switch idle {
        case ..<30: 2
        case ..<300: 8
        default: 30
        }
    }
}
