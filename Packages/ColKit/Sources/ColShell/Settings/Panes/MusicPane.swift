import AppKit
import ColCore
import SwiftUI

/// Music: the lyrics, where they show and how big, the user's own lyrics files, and the bars that follow the sound.
struct MusicPane: View {
    @State private var showsLyrics = Preferences.showsLyrics
    @State private var inClosedIsland = Preferences.showsLyricsInClosedIsland
    @AppStorage("lyricsTextSize") private var textSize = 1
    @State private var onLockScreen = Preferences.showsLyricsOnLockScreen
    @State private var lockScreenOn = Preferences.showsOnLockScreen
    @State private var onDesktop = Preferences.showsLyricsOnDesktop
    @State private var desktopPosition = Preferences.desktopLyricsPosition
    @State private var desktopSize = Preferences.desktopLyricsSize
    @State private var followsSound = Preferences.barsFollowSound
    @State private var hidden = LyricsOverridesStore.load().hiddenTracks
    @State private var permissions = PermissionCenter.shared

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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Lyrics come from LRCLIB, an open database written by its users. Col sends it only the title, the artist, the album and the length of the track, and keeps the answer on your Mac so each song is asked once.", bundle: .module)
                    if showsLyrics {
                        Text("Lyrics a little early or late, or not the right ones? The ⋯ button on the lyrics in the island moves them half a second at a time, lets you choose others among LRCLIB’s, or hides them for that song. Lyrics timed word by word fill as they are sung.", bundle: .module)
                    }
                }
            }
            if showsLyrics {
                Section {
                    IconToggle(symbol: "lock.fill", tint: .indigo, title: "Lyrics on the Lock Screen",
                               detail: LockScreenSpace.isSupported
                                   ? "Large, under the clock, while music plays, with the controls. It relies on private macOS functions, like Show on the Lock Screen."
                                   : "Not available on this version of macOS: it relies on private functions that macOS no longer offers.",
                               isOn: $onLockScreen)
                        .disabled(!LockScreenSpace.isSupported && !onLockScreen)
                        .onChange(of: onLockScreen) { Preferences.showsLyricsOnLockScreen = onLockScreen }
                    if onLockScreen, !lockScreenOn, LockScreenSpace.isSupported {
                        IconRow(symbol: "exclamationmark.triangle.fill", tint: .orange, title: Text("Show on the Lock Screen is off", bundle: .module),
                                detail: Text("The lyrics need it. It is in Live activities.", bundle: .module)) {
                            Button {
                                Preferences.showsOnLockScreen = true
                                lockScreenOn = true
                            } label: { Text("Turn On", bundle: .module) }
                        }
                    }
                    IconToggle(symbol: "menubar.dock.rectangle", tint: .teal, title: "Lyrics on the desktop",
                               detail: "The line being sung, large, above your wallpaper and below every window, while music plays. Clicks go through it.",
                               isOn: $onDesktop)
                        .onChange(of: onDesktop) { Preferences.showsLyricsOnDesktop = onDesktop }
                    if onDesktop {
                        Picker(selection: $desktopPosition) {
                            Text("Centre", bundle: .module).tag(DesktopLyricsPosition.center)
                            Text("Lower left", bundle: .module).tag(DesktopLyricsPosition.lowerLeft)
                            Text("Lower centre", bundle: .module).tag(DesktopLyricsPosition.lowerCenter)
                            Text("Lower right", bundle: .module).tag(DesktopLyricsPosition.lowerRight)
                        } label: {
                            Text("Position", bundle: .module)
                        }
                        .onChange(of: desktopPosition) { Preferences.desktopLyricsPosition = desktopPosition }
                        Picker(selection: $desktopSize) {
                            Text("Small", bundle: .module).tag(DesktopLyricsSize.small)
                            Text("Medium", bundle: .module).tag(DesktopLyricsSize.medium)
                            Text("Large", bundle: .module).tag(DesktopLyricsSize.large)
                        } label: {
                            Text("Size", bundle: .module)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: desktopSize) { Preferences.desktopLyricsSize = desktopSize }
                    }
                } header: {
                    Text("Beyond the island", bundle: .module)
                } footer: {
                    Text("Lyrics on the desktop follow Hide the island from screenshots and recordings, in General.", bundle: .module)
                }
            }
            if showsLyrics, !hidden.isEmpty {
                Section {
                    ForEach(hidden, id: \.key) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: entry.settings.title)
                                Text(verbatim: entry.settings.artist)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            Button {
                                var overrides = LyricsOverridesStore.load()
                                overrides.unhide(key: entry.key)
                                LyricsOverridesStore.save(overrides)
                                withAnimation { hidden = overrides.hiddenTracks }
                            } label: { Text("Show Lyrics", bundle: .module) }
                        }
                    }
                } header: {
                    Text("Songs with hidden lyrics", bundle: .module)
                }
            }
            Section {
                IconToggle(symbol: "waveform", tint: .pink, title: "Bars that follow the sound",
                           detail: SoundLevels.isSupported
                               ? "The bars beside the camera and a spectrum in the player move with the music itself. Asks to record system audio: the sound is analysed on your Mac as it plays, never recorded or sent."
                               : "Needs macOS 14.2 or later.",
                           isOn: $followsSound)
                    .disabled(!SoundLevels.isSupported && !followsSound)
                    .onChange(of: followsSound) {
                        Preferences.barsFollowSound = followsSound
                        // Asked when turned on, and only then; once refused, the row below opens System Settings.
                        if followsSound, permissions.canPrompt(.audioCapture) { permissions.request(.audioCapture) }
                    }
                if followsSound, SoundLevels.isSupported, !permissions.isGranted(.audioCapture) {
                    IconRow(symbol: PermissionCenter.Permission.audioCapture.symbol, tint: PermissionCenter.Permission.audioCapture.tint,
                            title: Text(PermissionCenter.Permission.audioCapture.title),
                            detail: Text("Until you allow it, the bars dance on their own, as before.", bundle: .module)) {
                        PermissionBadge(granted: false) { permissions.request(.audioCapture) }
                    }
                }
            } header: {
                Text("Sound", bundle: .module)
            }
            Section {
                IconRow(symbol: "doc.text.fill", tint: .gray, title: Text("Your own lyrics", bundle: .module),
                        detail: Text("Put a .lrc file named “Artist - Title.lrc” in this folder: Col prefers it to LRCLIB.", bundle: .module)) {
                    Button {
                        let folder = LyricsService.userFolder
                        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(folder)
                    } label: { Text("Open the Folder", bundle: .module) }
                }
                Link(destination: URL(string: "https://lrclib.net")!) { Text("Add or fix lyrics on LRCLIB", bundle: .module) }
            }
        }
        .onAppear {
            permissions.refresh()
            lockScreenOn = Preferences.showsOnLockScreen
            hidden = LyricsOverridesStore.load().hiddenTracks
        }
        .onReceive(NotificationCenter.default.publisher(for: LyricsOverridesStore.didChange)) { _ in
            hidden = LyricsOverridesStore.load().hiddenTracks
        }
    }
}
