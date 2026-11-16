import AppKit
import ColCore
import SwiftUI

/// The meeting the closed island counts down to: its colour, its title, its time, and Join when it has a call link.
struct MeetingCard: View {
    let event: CalendarModel.Event

    var body: some View {
        let tint = MeetingWatch.rgba(event.color).color
        HStack(spacing: 10) {
            Capsule().fill(tint).frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: event.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Group {
                    if event.start <= Date() {
                        Text("Now, until \(event.end.formatted(date: .omitted, time: .shortened))", bundle: .module)
                    } else {
                        Text("At \(event.start.formatted(date: .omitted, time: .shortened))", bundle: .module)
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 4)
            if let meeting = event.meeting {
                Button { NSWorkspace.shared.open(meeting) } label: {
                    Label { Text("Join", bundle: .module) } icon: { Image(systemName: "video.fill") }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(Capsule().fill(RGBA.green.color))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.fill))
    }
}

/// The microphone while an app listens or while it is muted, with the button that mutes it for every app.
struct MicrophoneRow: View {
    let microphone: MicrophoneMute

    static func shows(_ microphone: MicrophoneMute) -> Bool {
        Preferences.mutesMicrophone && microphone.isAvailable && (microphone.isMuted || !microphone.users.isEmpty)
    }

    var body: some View {
        let muted = microphone.isMuted
        let tint = (muted ? RGBA.red : RGBA.orange).color
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.16))
                Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("Microphone", bundle: .module)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                Group {
                    if muted {
                        Text("\(microphone.deviceName) is muted", bundle: .module)
                    } else {
                        Text("\(ListFormatter.localizedString(byJoining: microphone.users)) listening", bundle: .module)
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { IslandController.shared?.toggleMicrophone() } label: {
                Text(muted ? "Unmute" : "Mute", bundle: .module)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(muted ? .black : .white)
                    .padding(.horizontal, 14)
                    .frame(height: 26)
                    .background(Capsule().fill(muted ? Color.white : Color.white.opacity(0.13)))
            }
            .buttonStyle(PressableStyle())
            .help(Preferences.microphoneHotKeyEnabled ? Text("Also with Control-Option-Command-M", bundle: .module) : Text(verbatim: ""))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.fill))
        .animation(.spring(duration: 0.3), value: muted)
    }
}
