// scripts/fake-player.swift: publishes a silent track as "now playing", to work on Col's media features without
// playing sound. Usage: swift scripts/fake-player.swift [title] [artist] [seconds] [artwork image]
import AppKit
import AVFoundation
import MediaPlayer

let arguments = CommandLine.arguments
let title = arguments.count > 1 ? arguments[1] : "Midnight City"
let artist = arguments.count > 2 ? arguments[2] : "Col Test Band"
let length = arguments.count > 3 ? Double(arguments[3]) ?? 60 : 60

// Silent audio keeps the process an active player.
let engine = AVAudioEngine()
let source = AVAudioSourceNode { _, _, _, _ in noErr }
engine.attach(source)
engine.connect(source, to: engine.mainMixerNode, format: nil)
engine.mainMixerNode.outputVolume = 0
try? engine.start()

let size = NSSize(width: 600, height: 600)
let artwork = arguments.count > 4 ? NSImage(contentsOfFile: arguments[4]) ?? NSImage() : NSImage(size: size, flipped: false) { rect in
    let gradient = NSGradient(colors: [NSColor(red: 0.98, green: 0.35, blue: 0.45, alpha: 1), NSColor(red: 0.35, green: 0.2, blue: 0.95, alpha: 1)])
    gradient?.draw(in: rect, angle: 60)
    return true
}

let center = MPNowPlayingInfoCenter.default()
var started = Date()
var playing = true
func publish() {
    let elapsed = playing ? Date().timeIntervalSince(started) : center.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double ?? 0
    center.nowPlayingInfo = [
        MPMediaItemPropertyTitle: title,
        MPMediaItemPropertyArtist: artist,
        MPMediaItemPropertyAlbumTitle: ProcessInfo.processInfo.environment["ALBUM"] ?? "Col Sessions",
        MPMediaItemPropertyPlaybackDuration: length,
        MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
        MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
        MPMediaItemPropertyArtwork: MPMediaItemArtwork(boundsSize: size) { _ in artwork },
    ]
    center.playbackState = playing ? .playing : .paused
}
let commands = MPRemoteCommandCenter.shared()
commands.togglePlayPauseCommand.addTarget { _ in
    playing.toggle()
    if playing { started = Date().addingTimeInterval(-(center.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double ?? 0)) }
    publish(); return .success
}
commands.playCommand.addTarget { _ in if !playing { playing = true; publish() }; return .success }
commands.pauseCommand.addTarget { _ in if playing { playing = false; publish() }; return .success }
commands.nextTrackCommand.addTarget { _ in started = Date(); publish(); return .success }
commands.previousTrackCommand.addTarget { _ in started = Date(); publish(); return .success }
commands.changePlaybackPositionCommand.addTarget { event in
    let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime ?? 0
    started = Date().addingTimeInterval(-position); publish(); return .success
}
publish()
print("Now playing: \(title) by \(artist). Ctrl-C to stop.")
RunLoop.main.run()
