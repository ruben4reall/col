import AppKit

enum NSWorkspaceBridge {
    @MainActor static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
