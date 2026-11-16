import Foundation
import Testing
@testable import ColCore

struct SpectrumTests {
    @Test func bandsAreOrderedAndEachHasABinOfItsOwn() {
        for bands in [4, 12, 24] {
            let edges = SpectrumBands.edges(bands: bands, size: 4096, sampleRate: 48_000)
            #expect(edges.count == bands + 1)
            #expect(edges.first! >= 1)
            #expect(edges.last! <= 2048)
            #expect(zip(edges, edges.dropFirst()).allSatisfy { $0 < $1 })
        }
        // A small transform: the lowest bands crowd, each still a bin wide, and the last stays inside.
        let crowded = SpectrumBands.edges(bands: 24, size: 256, sampleRate: 48_000)
        #expect(zip(crowded, crowded.dropFirst()).allSatisfy { $0 < $1 })
        #expect(crowded.last! <= 128)
        #expect(SpectrumBands.edges(bands: 0, size: 4096, sampleRate: 48_000).isEmpty)
        #expect(SpectrumBands.edges(bands: 24, size: 32, sampleRate: 48_000).isEmpty)
    }

    @Test func loudnessReadsAsAHeight() {
        #expect(SpectrumBands.height(decibels: -100, band: 0, of: 24) == 0)
        #expect(SpectrumBands.height(decibels: 0, band: 0, of: 24) == 1)
        #expect(SpectrumBands.height(decibels: -.infinity, band: 3, of: 24) == 0)
        #expect(SpectrumBands.height(decibels: .nan, band: 3, of: 24) == 0)
        let middle = SpectrumBands.height(decibels: -42, band: 0, of: 24)
        #expect(middle > 0.4 && middle < 0.6)
        // The treble is lifted to stay level with the bass.
        #expect(SpectrumBands.height(decibels: -42, band: 23, of: 24) > middle)
    }

    @Test func barsRiseQuicklyAndFallSlowly() {
        let up = SpectrumBands.smoothed(0, toward: 1)
        let down = SpectrumBands.smoothed(1, toward: 0)
        #expect(up > 0.5)
        #expect(down > 0.5)
    }

    @Test func manyBandsBecomeFewKeepingTheirPeaks() {
        let levels: [Float] = [0.1, 0.9, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7]
        #expect(SpectrumBands.regroup(levels, into: 4) == [0.9, 0.3, 0.5, 0.7])
        #expect(SpectrumBands.regroup([0.5, 0.2], into: 4) == [0.5, 0.2, 0.2, 0.2])
        #expect(SpectrumBands.regroup([], into: 4).isEmpty)
    }

    #if canImport(Accelerate)
    private func feed(_ analyzer: SpectrumAnalyzer, frequency: Double, amplitude: Float, seconds: Double) -> [Float] {
        let rate = analyzer.sampleRate
        let count = Int(rate * seconds)
        let samples = (0..<count).map { amplitude * Float(sin(2 * Double.pi * frequency * Double($0) / rate)) }
        var levels = analyzer.levels
        // In buffers of 512 frames, as the audio thread hands them over.
        for start in stride(from: 0, to: count, by: 512) {
            let length = min(512, count - start)
            let due = samples.withUnsafeBufferPointer { analyzer.append($0.baseAddress! + start, count: length) }
            if due { levels = analyzer.analyze() }
        }
        return levels
    }

    @Test func aToneLightsItsOwnBand() throws {
        let analyzer = try #require(SpectrumAnalyzer(bands: 24, sampleRate: 48_000))
        let levels = feed(analyzer, frequency: 1000, amplitude: 0.5, seconds: 0.5)
        let loudest = try #require(levels.indices.max { levels[$0] < levels[$1] })
        let edges = SpectrumBands.edges(bands: 24, size: analyzer.size, sampleRate: 48_000)
        let bin = 1000 * Double(analyzer.size) / 48_000
        #expect(Double(edges[loudest]) <= bin + 1 && bin - 1 <= Double(edges[loudest + 1]))
        #expect(levels[loudest] > 0.8)
        // Far from the tone, the bars stay low.
        #expect(levels[0] < 0.2)
        #expect(levels[23] < 0.2)
    }

    @Test func silenceStaysFlatAndAResetClearsTheBars() throws {
        let analyzer = try #require(SpectrumAnalyzer(bands: 8, sampleRate: 44_100))
        #expect(feed(analyzer, frequency: 200, amplitude: 0, seconds: 0.3).allSatisfy { $0 == 0 })
        _ = feed(analyzer, frequency: 200, amplitude: 0.8, seconds: 0.3)
        #expect(analyzer.levels.contains { $0 > 0.5 })
        analyzer.reset()
        #expect(analyzer.levels.allSatisfy { $0 == 0 })
    }

    @Test func stereoIsMixedToOne() throws {
        let analyzer = try #require(SpectrumAnalyzer(bands: 8, sampleRate: 48_000))
        let frames = 48_000 / 4
        // The tone in the left channel only, silence in the right.
        var samples = [Float](repeating: 0, count: frames * 2)
        for frame in 0..<frames { samples[frame * 2] = 0.8 * Float(sin(2 * Double.pi * 440 * Double(frame) / 48_000)) }
        let due = samples.withUnsafeBufferPointer { analyzer.append(interleaved: $0.baseAddress!, frames: frames, channels: 2) }
        #expect(due)
        let levels = analyzer.analyze()
        #expect(levels.contains { $0 > 0.3 })
    }

    @Test func impossibleSettingsAreRefused() {
        #expect(SpectrumAnalyzer(bands: 0, sampleRate: 48_000) == nil)
        #expect(SpectrumAnalyzer(bands: 24, sampleRate: 100) == nil)
        #expect(SpectrumAnalyzer(bands: 24, sampleRate: 48_000, rate: 0) == nil)
    }
    #endif
}
