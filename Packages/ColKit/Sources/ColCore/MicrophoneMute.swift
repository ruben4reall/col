import Foundation

/// What Col muted, so that it can always be undone: each input device by its Core Audio UID, how it was muted (its own
/// mute, or its input volume turned to zero), and the volume it had. Kept in the settings, so a restart undoes a mute
/// that Col could not undo before it stopped.
public struct MicrophoneMuteLedger: Codable, Equatable, Sendable {
    public enum Method: String, Codable, Sendable {
        /// The device's own mute.
        case mute
        /// The input volume, turned to zero.
        case volume
    }

    public struct Entry: Codable, Equatable, Sendable {
        public var method: Method
        /// The input volume before Col turned it down; nil for a device muted with its own mute.
        public var volume: Double?

        public init(method: Method, volume: Double? = nil) {
            self.method = method
            self.volume = volume
        }
    }

    public private(set) var entries: [String: Entry] = [:]

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }

    public func entry(for uid: String) -> Entry? { entries[uid] }

    /// Col muted a device. A device muted again keeps the volume it had before the first time.
    public mutating func muted(_ uid: String, method: Method, volumeBefore: Double? = nil) {
        if let existing = entries[uid], existing.method == method { return }
        entries[uid] = Entry(method: method, volume: method == .volume ? volumeBefore : nil)
    }

    /// The device is no longer muted by Col: given back, or unmuted elsewhere.
    public mutating func forget(_ uid: String) {
        entries[uid] = nil
    }

    /// The volume a device turned down gets back: its own, else a usual level.
    public static func volumeToRestore(_ entry: Entry) -> Double {
        guard let volume = entry.volume, volume > 0.001 else { return 0.75 }
        return min(volume, 1)
    }

    /// What to do with each device Col muted, given whether it is muted now (nil when it is not connected): undo the
    /// mute of those still muted, forget those unmuted since, and keep the absent ones for when they come back.
    public func reconcile(isMuted: (String) -> Bool?) -> (restore: [String], forget: [String]) {
        var restore: [String] = []
        var forget: [String] = []
        for uid in entries.keys.sorted() {
            switch isMuted(uid) {
            case true?: restore.append(uid)
            case false?: forget.append(uid)
            case nil: break
            }
        }
        return (restore, forget)
    }
}
