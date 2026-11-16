import Foundation
import ColCore
import Observation

/// Activities other programs pushed, kept for the Live page.
@MainActor
@Observable
final class CustomActivities {
    struct Entry: Identifiable, Equatable {
        var id: String { request.id }
        var request: ActivityRequest
        var expires: Date?
        var finished: Bool
        var updated: Date
    }

    private(set) var entries: [Entry] = []

    /// Activities programs and devices may keep at once: one that keeps pushing new ids is refused past this.
    static let maximum = 32

    /// Shows or updates an activity. False when as many run as Col holds and this one is new.
    @discardableResult
    func upsert(_ request: ActivityRequest, now: Date = Date()) -> Bool {
        let entry = Entry(request: request, expires: request.ttl.map { now.addingTimeInterval($0) }, finished: false, updated: now)
        if let index = entries.firstIndex(where: { $0.id == request.id }) {
            entries[index] = entry
            return true
        }
        prune(now: now)
        guard entries.count < Self.maximum else { return false }
        entries.insert(entry, at: 0)
        return true
    }

    /// Marks an activity done; it lingers a moment with a check mark, then leaves.
    func finish(_ id: String, text: String?, now: Date = Date()) -> Entry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        entries[index].finished = true
        entries[index].request.progress = nil
        if let text { entries[index].request.text = text }
        entries[index].expires = now.addingTimeInterval(3)
        entries[index].updated = now
        return entries[index]
    }

    func remove(_ id: String) {
        entries.removeAll { $0.id == id }
    }

    func prune(now: Date = Date()) {
        entries.removeAll { ($0.expires ?? .distantFuture) <= now }
    }
}
