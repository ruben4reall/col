// swift scripts/record-film.swift <out.mov> <seconds> <pid,name,…> <x> <y> <width> <height>
// Records a rectangle of the main display (points, top-left origin) at 2x, without the cursor, showing only the
// windows of the given processes (a number is a process, a word an app's name, so an app relaunched mid-film stays
// in it), followed as they come and go: nothing else of the screen lands in the film.
import AVFoundation
import ScreenCaptureKit

final class Finished: NSObject, SCRecordingOutputDelegate {
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        FileHandle.standardError.write("recording failed: \(error)\n".data(using: .utf8)!)
    }
}

func filter(pids: Set<pid_t>, names: Set<String>) async throws -> SCContentFilter {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else { exit(1) }
    let windows = content.windows.filter {
        pids.contains($0.owningApplication?.processID ?? 0) || names.contains($0.owningApplication?.applicationName ?? "")
    }
    return SCContentFilter(display: display, including: windows)
}

let a = CommandLine.arguments
guard a.count >= 8 else { print("usage: record-film <out.mov> <seconds> <pid,name,…> <x> <y> <width> <height>"); exit(64) }
let output = URL(fileURLWithPath: a[1])
try? FileManager.default.removeItem(at: output)
let seconds = Double(a[2])!
let tokens = a[3].split(separator: ",").map(String.init)
let pids = Set(tokens.compactMap { pid_t($0) })
let names = Set(tokens.filter { pid_t($0) == nil })
let rect = CGRect(x: Double(a[4])!, y: Double(a[5])!, width: Double(a[6])!, height: Double(a[7])!)
let configuration = SCStreamConfiguration()
configuration.sourceRect = rect
configuration.width = Int(rect.width * 2)
configuration.height = Int(rect.height * 2)
configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
configuration.showsCursor = false
let stream = SCStream(filter: try await filter(pids: pids, names: names), configuration: configuration, delegate: nil)
let recording = SCRecordingOutputConfiguration()
recording.outputURL = output
recording.outputFileType = .mov
let delegate = Finished()
try stream.addRecordingOutput(SCRecordingOutput(configuration: recording, delegate: delegate))
try await stream.startCapture()
// Windows that appear later, such as the prompter's, join the film.
let started = Date()
while Date().timeIntervalSince(started) < seconds {
    try await Task.sleep(for: .milliseconds(250))
    try? await stream.updateContentFilter(try await filter(pids: pids, names: names))
}
try await stream.stopCapture()
