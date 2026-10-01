import AppKit
import SwiftUI

/// Music: the lyrics, where they show and how big, and the user's own lyrics files.
struct MusicPane: View {
    @State private var showsLyrics = Preferences.showsLyrics
    @State private var inClosedIsland = Preferences.showsLyricsInClosedIsland
    @AppStorage("lyricsTextSize") private var textSize = 1

    var body: some View {
        PaneScaffold(pane: .music) {
            Section {
                IconToggle(symbol: "quote.bubble.fill", tint: Color(red: 0.98, green: 0.24, blue: 0.4), title: "Synced lyrics",
                           detail: "The words of the song beside the player, line by line, whatever plays: Spotify, Apple Music, Deezer or your browser.", isOn: $showsLyrics)
                    .onChange(of: showsLyrics) { Preferences.showsLyrics = showsLyrics }
                if showsLyrics {
                    IconToggle(symbol: "capsule.lefthalf.filled", tint: .pink, title: "The line being sung in the closed island",
                               detail: "Right of the camera, in place of the bars, as far as the menu bar leaves room.", isOn: $inClosedIsland)
                        .onChange(of: inClosedIsland) { Preferences.showsLyricsInClosedIsland = inClosedIsland }
                    Picker(selection: $textSize) {
                        Text("Small", bundle: .module).tag(0)
                        Text("Medium", bundle: .module).tag(1)
                        Text("Large", bundle: .module).tag(2)
                    } label: {
                        Text("Text size", bundle: .module)
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Lyrics", bundle: .module)
            } footer: {
                Text("Lyrics come from LRCLIB, an open database written by its users. Islet sends it only the title, the artist, the album and the length of the track, and keeps the answer on your Mac so each song is asked once.", bundle: .module)
            }
            Section {
                IconRow(symbol: "doc.text.fill", tint: .gray, title: Text("Your own lyrics", bundle: .module),
                        detail: Text("Put a .lrc file named “Artist - Title.lrc” in this folder: Islet prefers it to LRCLIB.", bundle: .module)) {
                    Button {
                        let folder = LyricsService.userFolder
                        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(folder)
                    } label: { Text("Open the Folder", bundle: .module) }
                }
                Link(destination: URL(string: "https://lrclib.net")!) { Text("Add or fix lyrics on LRCLIB", bundle: .module) }
            }
        }
    }
}
