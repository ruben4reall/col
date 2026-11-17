import AppKit
import TiroirCore
import TiroirUI
import UniformTypeIdentifiers

/// The settings as a file (Settings, General): a copy to keep, or the same setup on another Mac.
@MainActor
enum SettingsFile {
    static func export(_ settings: TiroirSettings) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(Strings.exportFileName).json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url, let data = SettingsStore.data(settings, pretty: true) else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            alert(error.localizedDescription)
        }
    }

    /// Asks for a file, reads it and confirms the replacement. Nil when the person cancels or the file cannot be used,
    /// which they are told.
    static func chooseAndRead() -> TiroirSettings? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let data = try? Data(contentsOf: url) else {
            alert(Strings.importUnreadable)
            return nil
        }
        switch SettingsStore.read(data) {
        case .failure(.unreadable):
            alert(Strings.importUnreadable)
            return nil
        case .failure(.newerVersion):
            alert(Strings.importFromNewerVersion)
            return nil
        case .success(let settings):
            let confirm = NSAlert()
            confirm.messageText = Strings.importQuestion(url.deletingPathExtension().lastPathComponent)
            confirm.informativeText = Strings.importExplanation
            confirm.addButton(withTitle: Strings.replace)
            confirm.addButton(withTitle: Strings.cancel)
            return confirm.runModal() == .alertFirstButtonReturn ? settings : nil
        }
    }

    private static func alert(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.runModal()
    }
}
