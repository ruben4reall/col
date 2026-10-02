import AppKit
import Observation
import QuickLookThumbnailing

/// Files dropped on the island, kept by reference until the user takes them somewhere else.
@MainActor
@Observable
final class ShelfModel {
    struct Item: Identifiable, Equatable {
        var id: URL { url }
        var url: URL
        var thumbnail: NSImage?
    }

    private(set) var items: [Item] = []
    /// True while files are dragged over the island.
    var isTargeted = false
    /// False while demo files stand in for the user's: nothing is saved then.
    @ObservationIgnored private var persists = true

    init() {
        restore()
    }

    func add(_ urls: [URL]) {
        for url in urls where !items.contains(where: { $0.url == url }) {
            items.append(Item(url: url, thumbnail: NSWorkspace.shared.icon(forFile: url.path)))
            loadThumbnail(for: url)
        }
        save()
    }

    func remove(_ item: Item) {
        items.removeAll { $0.url == item.url }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    /// For screenshots: the files of a folder stand in for the user's shelf, which stays untouched.
    func showDemo(folder: URL) {
        persists = false
        let urls = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        items = urls.map { Item(url: $0, thumbnail: NSWorkspace.shared.icon(forFile: $0.path)) }
        urls.forEach(loadThumbnail(for:))
    }

    func open(_ item: Item) {
        NSWorkspace.shared.open(item.url)
    }

    func reveal(_ item: Item) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// Sends every file on the shelf with AirDrop.
    func airDrop() {
        guard !items.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate()
        service.perform(withItems: items.map(\.url))
    }

    var canAirDrop: Bool {
        !items.isEmpty && NSSharingService(named: .sendViaAirDrop)?.canPerform(withItems: items.map(\.url)) == true
    }

    private func loadThumbnail(for url: URL) {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 96, height: 96), scale: 2, representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let image = representation?.nsImage else { return }
            let thumbnail = image
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let index = self.items.firstIndex(where: { $0.url == url }) else { return }
                    self.items[index].thumbnail = thumbnail
                }
            }
        }
    }

    // MARK: Persistence

    /// The shelf survives a restart as bookmarks, so renamed or moved files are still found.
    private static let key = "shelfBookmarks"

    private func save() {
        guard persists else { return }
        let bookmarks = items.compactMap { try? $0.url.bookmarkData(options: .minimalBookmark) }
        UserDefaults.standard.set(bookmarks, forKey: Self.key)
    }

    private func restore() {
        let bookmarks = UserDefaults.standard.array(forKey: Self.key) as? [Data] ?? []
        var stale = false
        let urls = bookmarks.compactMap { data -> URL? in
            var isStale = false
            let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale)
            stale = stale || isStale
            return url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        }
        items = urls.map { Item(url: $0, thumbnail: NSWorkspace.shared.icon(forFile: $0.path)) }
        urls.forEach(loadThumbnail(for:))
        if stale || urls.count != bookmarks.count { save() }
    }
}
