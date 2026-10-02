// swift scripts/encode-film.swift <in.mov> <out.mp4> <width> <bitrate>: re-encodes a film in H.264 (High profile)
// for the website, at a width and an average bitrate in bits per second.
import AVFoundation
let a = CommandLine.arguments
let asset = AVURLAsset(url: URL(fileURLWithPath: a[1]))
let out = URL(fileURLWithPath: a[2])
try? FileManager.default.removeItem(at: out)
let width = Int(a[3])!, bitrate = Int(a[4])!
let track = try await asset.loadTracks(withMediaType: .video).first!
let natural = try await track.load(.naturalSize)
let height = Int((natural.height * CGFloat(width) / natural.width / 2).rounded()) * 2
let reader = try! AVAssetReader(asset: asset)
let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
reader.add(readerOutput)
let writer = try! AVAssetWriter(outputURL: out, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, AVVideoMaxKeyFrameIntervalKey: 60],
])
input.expectsMediaDataInRealTime = false
writer.add(input)
reader.startReading()
writer.startWriting()
writer.startSession(atSourceTime: .zero)
// The writer asks for frames until the reader runs out, then finishes the file.
let queue = DispatchQueue(label: "encode-film")
await withCheckedContinuation { (finished: CheckedContinuation<Void, Never>) in
    input.requestMediaDataWhenReady(on: queue) {
        while input.isReadyForMoreMediaData {
            guard let sample = readerOutput.copyNextSampleBuffer() else {
                input.markAsFinished()
                writer.finishWriting { finished.resume() }
                return
            }
            input.append(sample)
        }
    }
}
print(out.path)
