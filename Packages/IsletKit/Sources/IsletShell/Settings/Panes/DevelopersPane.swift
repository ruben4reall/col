import SwiftUI

struct DevelopersPane: View {
    let extensions: ExtensionRunner?
    @State private var cliMessage: String?
    @State private var cliInstalled = FileManager.default.fileExists(atPath: CommandLineInstaller.linkURL.path)

    var body: some View {
        PaneScaffold(pane: .developers) {
            Section {
                IconRow(symbol: "terminal.fill", tint: .black, title: Text("The islet command", bundle: .module),
                        detail: Text(cliMessage ?? String(localized: "Push live activities from any script: islet push build --progress 40%", bundle: .module))) {
                    if cliInstalled {
                        Label { Text("Installed", bundle: .module) } icon: { Image(systemName: "checkmark.circle.fill") }
                            .foregroundStyle(.green)
                            .fixedSize()
                    } else {
                        Button {
                            cliMessage = CommandLineInstaller.install()
                            cliInstalled = FileManager.default.fileExists(atPath: CommandLineInstaller.linkURL.path)
                        } label: { Text("Install", bundle: .module) }
                    }
                }
            } header: {
                Text("Programmable notch", bundle: .module)
            } footer: {
                Text("Scripts, Shortcuts and islet:// links all reach the same local API. Nothing listens on the network.", bundle: .module)
            }
            if let extensions {
                Section {
                    if extensions.installed.isEmpty {
                        Text("Put an extension folder here, with an extension.json and a script. Each one shows what its script prints.", bundle: .module)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(extensions.installed) { item in
                        Toggle(isOn: Binding(get: { item.enabled }, set: { extensions.setEnabled($0, folder: item.folder) })) {
                            Text(item.manifest.name)
                            Text(item.lastError ?? item.manifest.description ?? item.manifest.command)
                                .foregroundStyle(item.lastError == nil ? Color.secondary : Color.orange)
                        }
                    }
                    HStack {
                        Button { extensions.revealFolder() } label: { Text("Open the Extensions Folder", bundle: .module) }
                        Button { extensions.reload() } label: { Text("Reload", bundle: .module) }
                    }
                } header: {
                    Text("Extensions", bundle: .module)
                }
            }
            Section {
                Link(destination: URL(string: "https://github.com/ruben4reall/islet/blob/main/docs/api.md")!) { Text("API reference", bundle: .module) }
                Link(destination: URL(string: "https://github.com/ruben4reall/islet/blob/main/docs/extensions.md")!) { Text("Writing an extension", bundle: .module) }
            } header: {
                Text("Documentation", bundle: .module)
            }
        }
    }
}
