import ColCore
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
    @State private var ranking = Preferences.activityRanking
    @State private var backlight = Preferences.showsKeyboardBacklight
    @State private var capsLock = Preferences.showsCapsLock
    @State private var mute = Preferences.mutesMicrophone
    @State private var accessories = Preferences.showsAccessoryBatteries
    @State private var meeting = Preferences.showsNextMeeting
    @State private var meetingLead = Preferences.meetingLeadMinutes
    @State private var permissions = PermissionCenter.shared

    var body: some View {
        PaneScaffold(pane: .activities) {
            Section {
                ForEach(Array(ranking.enumerated()), id: \.element) { index, source in
                    HStack(spacing: 12) {
                        Text(verbatim: "\(index + 1)")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        IconTile(symbol: source.symbol, tint: source.tint)
                        Text(source.title)
                        Spacer(minLength: 8)
                        HStack(spacing: 2) {
                            Button { move(source, by: -1) } label: { Image(systemName: "chevron.up") }
                                .disabled(index == 0)
                                .help(Text("Move up", bundle: .module))
                            Button { move(source, by: 1) } label: { Image(systemName: "chevron.down") }
                                .disabled(index == ranking.count - 1)
                                .help(Text("Move down", bundle: .module))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("When several things run", bundle: .module)
            } footer: {
                Text("The closed island shows the highest one in this list. Volume, brightness, alerts and requests always come first.", bundle: .module)
            }
            Section {
                IconToggle(symbol: "music.note", tint: .pink, title: "Music beside the camera", detail: "The cover and the bars while something plays.", isOn: $media)
                    .onChange(of: media) { Preferences.showsMediaActivity = media }
                IconToggle(symbol: "text.badge.plus", tint: .pink, title: "Announce new tracks", detail: "The title shows for a moment when a track starts.", isOn: $tracks)
                    .onChange(of: tracks) { Preferences.showsTrackChanges = tracks }
            } header: {
                Text("Music", bundle: .module)
            }
            Section {
                IconToggle(symbol: "speaker.wave.2.fill", tint: .blue, title: "Replace the volume and brightness displays", detail: needsAccessibility, isOn: $hud)
                    .onChange(of: hud) { Preferences.replacesSystemHUD = hud }
                IconToggle(symbol: "airpodspro", tint: .gray, title: "Headphones and speakers", detail: "The device the moment it connects.", isOn: $devices)
                    .onChange(of: devices) { Preferences.showsAudioDevices = devices }
                IconToggle(symbol: "battery.75percent", tint: .gray, title: "Battery card for headphones", detail: "Opens the island with the battery of each earbud and the case. Needs Bluetooth.", isOn: $deviceCard)
                    .onChange(of: deviceCard) { Preferences.showsDeviceCard = deviceCard }
                IconToggle(symbol: "battery.100.bolt", tint: .green, title: "Charging and low battery", detail: "When you plug in, and at 20 % and 10 %.", isOn: $battery)
                    .onChange(of: battery) { Preferences.showsBattery = battery }
                IconToggle(symbol: "mic.fill", tint: .orange, title: "Microphone and camera in use", detail: "Which app is listening or filming.", isOn: $privacy)
                    .onChange(of: privacy) { Preferences.showsMicrophoneAndCamera = privacy }
                IconToggle(symbol: "mic.slash.fill", tint: .red, title: "Mute the microphone from the island",
                           detail: "A Mute button on the Live page mutes your Mac’s default microphone, and the island shows it in red while it stays muted. Turning this off, or quitting Col, unmutes it.", isOn: $mute)
                    .onChange(of: mute) { Preferences.mutesMicrophone = mute }
                IconToggle(symbol: "light.max", tint: .gray, title: "Keyboard backlight",
                           detail: backlightDetail, isOn: $backlight)
                    .onChange(of: backlight) { Preferences.showsKeyboardBacklight = backlight }
                IconToggle(symbol: "capslock.fill", tint: .green, title: "Caps Lock",
                           detail: capsLockDetail, isOn: $capsLock)
                    .onChange(of: capsLock) {
                        Preferences.showsCapsLock = capsLock
                        if capsLock, !permissions.isGranted(.accessibility) { permissions.request(.accessibility) }
                    }
                IconToggle(symbol: "magicmouse.fill", tint: .gray, title: "Accessories’ batteries",
                           detail: "Your mouse, keyboard and trackpad in the Devices widget, and a word when one falls under 15 %.", isOn: $accessories)
                    .onChange(of: accessories) { Preferences.showsAccessoryBatteries = accessories }
            } header: {
                Text("System", bundle: .module)
            }
            Section {
                IconToggle(symbol: "calendar", tint: .red, title: "Next meeting",
                           detail: "A countdown in its calendar’s colour before an event starts, and Join on the Live page when it has a call link. Uses the agenda’s access to Calendars.", isOn: $meeting)
                    .onChange(of: meeting) {
                        Preferences.showsNextMeeting = meeting
                        if meeting, permissions.canPrompt(.calendars) { permissions.request(.calendars) }
                    }
                if meeting {
                    Stepper(value: $meetingLead, in: MeetingCountdown.leadRange) {
                        Text("Starts \(meetingLead) min before", bundle: .module)
                    }
                    .onChange(of: meetingLead) { Preferences.meetingLeadMinutes = meetingLead }
                }
            } header: {
                Text("Calendar", bundle: .module)
            }
            Section {
                IconToggle(symbol: "sparkles", tint: SettingsPane.aiApps.tint, title: "AI apps", detail: "Sessions at work and the requests that wait for you.", isOn: $agents)
                    .onChange(of: agents) { Preferences.showsAgents = agents }
                IconToggle(symbol: "arrow.down.circle.fill", tint: .blue, title: "Downloads in progress", detail: "Files your browser is still writing. Asks to read the Downloads folder.", isOn: $downloads)
                    .onChange(of: downloads) { Preferences.watchesDownloads = downloads }
                IconToggle(symbol: "lock.fill", tint: .indigo, title: "Show on the Lock Screen",
                           detail: LockScreenSpace.isSupported ? "Beta. Takes effect the next time Col opens." : "Not available on this version of macOS: it relies on private functions that macOS no longer offers.",
                           isOn: $lockScreen)
                    .disabled(!LockScreenSpace.isSupported && !lockScreen)
                    .onChange(of: lockScreen) { Preferences.showsOnLockScreen = lockScreen }
            } header: {
                Text("More", bundle: .module)
            }
        }
    }

    private func move(_ source: ActivitySource, by offset: Int) {
        guard let index = ranking.firstIndex(of: source) else { return }
        let target = min(max(index + offset, 0), ranking.count - 1)
        withAnimation(.spring(duration: 0.3, bounce: 0.2)) { ranking.swapAt(index, target) }
        Preferences.activityRanking = ranking
    }
}

extension ActivitySource {
    var title: LocalizedStringResource {
        switch self {
        case .privacy: LocalizedStringResource("Microphone and camera in use", bundle: .settings)
        case .meetings: LocalizedStringResource("Next meeting", bundle: .settings)
        case .agents: LocalizedStringResource("AI apps at work", bundle: .settings)
        case .timers: LocalizedStringResource("Timers", bundle: .settings)
        case .downloads: LocalizedStringResource("Downloads in progress", bundle: .settings)
        case .scripts: LocalizedStringResource("Activities from scripts and extensions", bundle: .settings)
        case .music: LocalizedStringResource("Music", bundle: .settings)
        case .keepAwake: LocalizedStringResource("Keep awake", bundle: .settings)
        }
    }

    var symbol: String {
        switch self {
        case .privacy: "mic.fill"
        case .meetings: "calendar"
        case .agents: "sparkles"
        case .timers: "timer"
        case .downloads: "arrow.down.circle.fill"
        case .scripts: "terminal.fill"
        case .music: "music.note"
        case .keepAwake: "cup.and.saucer.fill"
        }
    }

    var tint: Color {
        switch self {
        case .privacy: .orange
        case .meetings: .red
        case .agents: SettingsPane.aiApps.tint
        case .timers: .orange
        case .downloads: .blue
        case .scripts: .black
        case .music: .pink
        case .keepAwake: .brown
        }
    }
}

/// The permission's name as System Settings shows it: macOS 27 renamed it.
private var needsAccessibility: LocalizedStringKey {
    ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
        ? "Needs Device Control and Data Access."
        : "Needs Accessibility."
}

private var backlightDetail: LocalizedStringKey {
    ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
        ? "The level, as for brightness, on the Macs with backlight keys. Needs Device Control and Data Access."
        : "The level, as for brightness, on the Macs with backlight keys. Needs Accessibility."
}

private var capsLockDetail: LocalizedStringKey {
    ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
        ? "On or off, for a moment. Col sees the modifier keys only, never what you type. Needs Device Control and Data Access."
        : "On or off, for a moment. Col sees the modifier keys only, never what you type. Needs Accessibility."
}
