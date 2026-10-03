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
                    Text(verbatim: "Col").font(.system(size: 26, weight: .bold))
                    Text("The notch, made useful.", bundle: .module).foregroundStyle(.secondary)
                    Text("Version \(Self.version)", bundle: .module)
                        .font(.callout).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            Section {
                IconRow(symbol: "network", tint: .blue, title: Text("What goes online", bundle: .module),
                        detail: Text("The update check, once a day, on the Col website; you can turn it off in General. While lyrics are on, the title, artist, album and length of the song you play, sent to LRCLIB. The AI servers you add, and your questions only to the one you pick; Ollama or LM Studio installed on this Mac, asked on this Mac only. The prompter’s phone remote, on your local network, only while you turn it on. Nothing else: no account, no analytics.", bundle: .module)) {
                    EmptyView()
                }
            } header: {
                Text("Privacy", bundle: .module)
            }
            Section {
                Link(destination: URL(string: "https://getcol.vercel.app")!) { Text("Website", bundle: .module) }
                Link(destination: URL(string: "https://github.com/ruben4reall/col")!) { Text("Source code on GitHub", bundle: .module) }
                Link(destination: URL(string: "https://github.com/ruben4reall/col/issues")!) { Text("Report a problem", bundle: .module) }
            }
            Section {
                Button(role: .destructive) { NSApp.terminate(nil) } label: { Text("Quit Col", bundle: .module) }
            } footer: {
                Text("MIT License. Col is not affiliated with Apple.", bundle: .module)
            }
        }
    }
}
