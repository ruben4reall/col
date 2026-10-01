import SwiftUI

/// What the closed island may show beside the camera. Alerts and brief displays (volume, a request) always win over
/// what plays in the background.
struct LiveActivitiesPane: View {
    @State private var media = Preferences.showsMediaActivity
    @State private var tracks = Preferences.showsTrackChanges
    @State private var hud = Preferences.replacesSystemHUD
    @State private var devices = Preferences.showsAudioDevices
    @State private var deviceCard = Preferences.showsDeviceCard
    @State private var battery = Preferences.showsBattery
    @State private var privacy = Preferences.showsMicrophoneAndCamera
    @State private var downloads = Preferences.watchesDownloads
    @State private var agents = Preferences.showsAgents
    @State private var lockScreen = Preferences.showsOnLockScreen

    var body: some View {
        PaneScaffold(pane: .activities) {
            Section {
                IconToggle(symbol: "music.note", tint: .pink, title: "Music beside the camera", detail: "The cover and the bars while something plays.", isOn: $media)
                    .onChange(of: media) { Preferences.showsMediaActivity = media }
                IconToggle(symbol: "text.badge.plus", tint: .pink, title: "Announce new tracks", detail: "The title shows for a moment when a track starts.", isOn: $tracks)
                    .onChange(of: tracks) { Preferences.showsTrackChanges = tracks }
            } header: {
                Text("Music", bundle: .module)
            }
            Section {
                IconToggle(symbol: "speaker.wave.2.fill", tint: .blue, title: "Replace the volume and brightness displays", detail: "Needs Accessibility.", isOn: $hud)
                    .onChange(of: hud) { Preferences.replacesSystemHUD = hud }
                IconToggle(symbol: "airpodspro", tint: .gray, title: "Headphones and speakers", detail: "The device the moment it connects.", isOn: $devices)
                    .onChange(of: devices) { Preferences.showsAudioDevices = devices }
                IconToggle(symbol: "battery.75percent", tint: .gray, title: "Battery card for headphones", detail: "Opens the island with the battery of each earbud and the case. Needs Bluetooth.", isOn: $deviceCard)
                    .onChange(of: deviceCard) { Preferences.showsDeviceCard = deviceCard }
                IconToggle(symbol: "battery.100.bolt", tint: .green, title: "Charging and low battery", detail: "When you plug in, and at 20 % and 10 %.", isOn: $battery)
                    .onChange(of: battery) { Preferences.showsBattery = battery }
                IconToggle(symbol: "mic.fill", tint: .orange, title: "Microphone and camera in use", detail: "Which app is listening or filming.", isOn: $privacy)
                    .onChange(of: privacy) { Preferences.showsMicrophoneAndCamera = privacy }
            } header: {
                Text("System", bundle: .module)
            }
            Section {
                IconToggle(symbol: "sparkles", tint: SettingsPane.aiApps.tint, title: "AI apps", detail: "Sessions at work and the requests that wait for you.", isOn: $agents)
                    .onChange(of: agents) { Preferences.showsAgents = agents }
                IconToggle(symbol: "arrow.down.circle.fill", tint: .blue, title: "Downloads in progress", detail: "Files your browser is still writing. Asks to read the Downloads folder.", isOn: $downloads)
                    .onChange(of: downloads) { Preferences.watchesDownloads = downloads }
                IconToggle(symbol: "lock.fill", tint: .indigo, title: "Show on the Lock Screen", detail: "Beta. Takes effect the next time Islet opens.", isOn: $lockScreen)
                    .onChange(of: lockScreen) { Preferences.showsOnLockScreen = lockScreen }
            } header: {
                Text("More", bundle: .module)
            } footer: {
                Text("Volume, brightness and requests always come first; music waits behind everything else. Timers and activities pushed by scripts always show.", bundle: .module)
            }
        }
    }
}
