import AppKit
import TiroirApp
import TiroirSystem
import TiroirUI

/// The drawers themselves, in Col's process: Tiroir's coordinator, given Col's preferences, Col's permission, Col's
/// Dock icon and a word to the island each time the menu bar changes. macOS 26 and later.
@available(macOS 26, *)
@MainActor
final class ColDrawersRunner: DrawersRunner {
    private let coordinator: Coordinator

    init(drawers: MenuBarDrawers) {
        let host = DrawersHost(
            defaults: .standard,
            settingsKey: MenuBarDrawers.settingsKey,
            requestAccessibility: { PermissionCenter.shared.request(.accessibility) },
            moveToApplications: { [weak drawers] in drawers?.moveToApplications?() },
            windowOpened: { WindowPresence.shared.add($0) },
            windowClosed: { window in
                WindowPresence.shared.remove(window)
                window.emptyWhenClosed()
            },
            menuBarChanged: { [weak drawers] in drawers?.drawersChangedTheMenuBar() })
        coordinator = Coordinator(options: .current(), host: host)
        let coordinator = coordinator
        Task { await coordinator.start() }
    }

    func stop() {
        coordinator.shutdown()
    }

    func openSettings(_ pane: DrawersPane?) {
        coordinator.openSettings(pane.flatMap { TiroirUI.SettingsPane(rawValue: $0.rawValue) })
    }

    func showSmartSort() {
        coordinator.showWelcome(step: .sort)
    }

    var ownItemFrames: [CGRect] { coordinator.ownItemFrames }

    var issue: DrawersIssue? {
        switch coordinator.interface.engineStatus {
        case .ready: nil
        case .needsAccessibility: .needsPermission
        case .needsApplicationsFolder: .needsApplicationsFolder
        case .unavailable(let detail): .unavailable(detail)
        }
    }

    var drawerCount: Int { coordinator.interface.settings.layout.drawers.count }
}
