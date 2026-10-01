import Foundation
import ColCore

/// Watches the Downloads folder for files browsers are still writing. Off unless the user turns it on: reading
/// Downloads asks for macOS's permission the first time.
@MainActor
final class DownloadsMonitor {
    var onEvent: ((DownloadTracker.Event) -> Void)?
    private var tracker = DownloadTracker()
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1

    private var folder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    func start() {
        guard source == nil else { return }
        descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        _ = tracker.update(listing: listing())
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        let descriptor = descriptor
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func listing() -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    private func scan() {
        tracker.update(listing: listing()).forEach { onEvent?($0) }
    }
}
