import SwiftUI

struct PermissionsPane: View {
    @State private var center = PermissionCenter.shared

    var body: some View {
        PaneScaffold(pane: .permissions) {
            Section {
                ForEach(PermissionCenter.Permission.allCases) { permission in
                    HStack(spacing: 12) {
                        IconTile(symbol: permission.symbol, tint: permission.tint, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(permission.title)
                                Text(permission.feature)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                            }
                            Text(permission.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        PermissionBadge(granted: center.isGranted(permission)) { center.request(permission) }
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if center.awaitingAccessibility {
                        Text("Turn Islet on in the list that just opened, then come back here.", bundle: .module)
                            .foregroundStyle(.orange)
                    }
                    Text("Islet never asks for Screen Recording, Full Disk Access or Input Monitoring. It sees that the microphone is in use without ever listening to it.", bundle: .module)
                }
            }
            Section {
                IconRow(symbol: "arrow.down.circle.fill", tint: .blue, title: Text("Downloads folder", bundle: .module),
                        detail: Text("Asked when you turn on Downloads in progress, so Islet can see files still being written.", bundle: .module)) {
                    Button { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!) } label: {
                        Text("Open Settings…", bundle: .module)
                    }
                }
            } header: {
                Text("Files", bundle: .module)
            }
        }
        .onAppear { center.refresh() }
    }
}
