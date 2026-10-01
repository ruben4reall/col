import AppKit
import SwiftUI

struct AboutPane: View {
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }

    var body: some View {
        PaneScaffold(pane: .about) {
            Section {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                    Text(verbatim: "Islet").font(.system(size: 26, weight: .bold))
                    Text("The notch, made useful.", bundle: .module).foregroundStyle(.secondary)
                    Text("Version \(Self.version)", bundle: .module)
                        .font(.callout).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            Section {
                IconRow(symbol: "network", tint: .blue, title: Text("Updates only", bundle: .module),
                        detail: Text("Islet goes online only to check for its own updates, on the Islet website. No account, no analytics: what it shows stays on your Mac.", bundle: .module)) {
                    EmptyView()
                }
            } header: {
                Text("Privacy", bundle: .module)
            }
            Section {
                Link(destination: URL(string: "https://getislet.vercel.app")!) { Text("Website", bundle: .module) }
                Link(destination: URL(string: "https://github.com/ruben4reall/islet")!) { Text("Source code on GitHub", bundle: .module) }
                Link(destination: URL(string: "https://github.com/ruben4reall/islet/issues")!) { Text("Report a problem", bundle: .module) }
            }
            Section {
                Button(role: .destructive) { NSApp.terminate(nil) } label: { Text("Quit Islet", bundle: .module) }
            } footer: {
                Text("MIT License. Islet is not affiliated with Apple.", bundle: .module)
            }
        }
    }
}
