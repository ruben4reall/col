import SwiftUI

/// Settings, Menu Bar: the switch that tidies the menu bar's icons into drawers, what the drawers wait for when they
/// cannot work yet, and the way to their own settings window.
struct MenuBarPane: View {
    @State private var drawers = MenuBarDrawers.shared
    @State private var permissions = PermissionCenter.shared
    @State private var isOn = MenuBarDrawers.shared.isEnabled

    var body: some View {
        PaneScaffold(pane: .menuBar) {
            Section {
                IconToggle(symbol: "menubar.rectangle", tint: SettingsPane.menuBar.tint, title: "Tidy the menu bar into drawers",
                           detail: "Icons you rarely look at wait in drawers, one click away, and the island gets more room beside the notch.",
                           isOn: $isOn)
                    .disabled(!drawers.isSupportedHere)
                    .onChange(of: isOn) { drawers.setEnabled(isOn) }
            } footer: {
                if !drawers.isSupportedHere {
                    Text("Needs macOS 26 or later.", bundle: .module)
                } else if isOn {
                    VStack(alignment: .leading, spacing: 6) {
                        if drawers.importedFromTiroir {
                            Text("Tiroir’s drawers, profiles and look came along.", bundle: .module)
                        }
                        Text("Turn this off, or quit Col, and every icon comes back to the menu bar.", bundle: .module)
                    }
                }
            }
            if isOn, drawers.isSupportedHere {
                waiting
                if drawers.status == .running, drawers.runner?.issue == nil {
                    settings
                }
            }
        }
        .onAppear {
            permissions.refresh()
            isOn = drawers.isEnabled
        }
    }

    /// What keeps the drawers from working, if anything, and the one thing to do about it.
    @ViewBuilder private var waiting: some View {
        if drawers.status == .yieldsToTiroir {
            Section {
                IconRow(symbol: "archivebox.fill", tint: .orange, title: Text("Tiroir is open", bundle: .module),
                        detail: Text("Tiroir already tidies your menu bar. Quit it, and Col takes over with the same drawers.", bundle: .module)) {
                    Button { drawers.quitStandalone() } label: { Text("Quit Tiroir", bundle: .module) }
                }
            }
        } else if !permissions.isGranted(.accessibility) || drawers.runner?.issue == .needsPermission {
            Section {
                IconRow(symbol: PermissionCenter.Permission.accessibility.symbol, tint: PermissionCenter.Permission.accessibility.tint,
                        title: Text(PermissionCenter.Permission.accessibility.title),
                        detail: Text("The drawers need it to see which app owns each icon and to open them. Until then, every icon stays in the menu bar.", bundle: .module)) {
                    PermissionBadge(granted: permissions.isGranted(.accessibility)) { permissions.request(.accessibility) }
                }
            } footer: {
                if permissions.awaitingAccessibility {
                    Text("Turn Col on in the list that just opened, then come back here.", bundle: .module)
                        .foregroundStyle(.orange)
                }
            }
        } else if drawers.runner?.issue == .needsApplicationsFolder {
            Section {
                IconRow(symbol: "folder.fill", tint: .blue, title: Text("Move Col to the Applications folder", bundle: .module),
                        detail: Text("macOS 27 lets only apps in the Applications folder change the menu bar. Until then, every icon stays in the menu bar.", bundle: .module)) {
                    if !AppLocation.isDevelopmentBuild, let move = drawers.moveToApplications {
                        Button { move() } label: { Text("Move to Applications", bundle: .module) }
                    }
                }
            }
        } else if case .unavailable(let detail) = drawers.runner?.issue {
            Section {
                IconRow(symbol: "exclamationmark.triangle.fill", tint: .orange,
                        title: Text("This version of macOS changed what the drawers rely on", bundle: .module),
                        detail: Text("Every icon stays in the menu bar (\(detail)).", bundle: .module)) {
                    EmptyView()
                }
            }
        }
    }

    /// The drawers' own settings, in their window.
    @ViewBuilder private var settings: some View {
        Section {
            IconRow(symbol: "rectangle.3.group.fill", tint: .teal, title: Text("Layout and drawers", bundle: .module),
                    detail: Text("Drag icons between the menu bar, your drawers and Hidden; name each drawer and choose its icon.", bundle: .module)) {
                Button { drawers.runner?.openSettings(.layout) } label: { Text("Arrange…", bundle: .module) }
            }
            IconRow(symbol: "paintbrush.pointed.fill", tint: .indigo, title: Text("Look, triggers and shortcuts", bundle: .module),
                    detail: Text("A tint for the menu bar, profiles that switch by themselves, and a shortcut for any icon.", bundle: .module)) {
                Button { drawers.runner?.openSettings(.appearance) } label: { Text("Open…", bundle: .module) }
            }
            IconRow(symbol: "wand.and.stars", tint: .purple, title: Text("Smart Sort", bundle: .module),
                    detail: Text("Sorts every icon again, by purpose or by developer, and shows the result before it applies.", bundle: .module)) {
                Button { drawers.runner?.showSmartSort() } label: { Text("Sort Again…", bundle: .module) }
            }
        } header: {
            Text("Drawers", bundle: .module)
        }
    }
}
