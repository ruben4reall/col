import Foundation

/// The arithmetic of bars that follow the sound: which frequencies each bar covers, how loud reads how tall, and how
/// bars rise and fall.
public enum SpectrumBands {
    /// Bars cover the range of music, from the kick drum to the cymbals.
    public static let lowest = 50.0
    public static let highest = 16_000.0
    /// The quietest sound a bar shows, and the loudest, in decibels below full scale.
    public static let floor = -72.0
    public static let ceiling = -12.0
    /// Music falls off faster than pink noise toward the treble: the highest bar gets this many decibels more than the
    /// lowest, the others in proportion, so the bars stay even.
    public static let tilt = 6.0

    /// The FFT bins where each band starts, `bands + 1` of them, spaced evenly in octaves. Every band has at least one
    /// bin of its own, and none reaches bin 0, which holds no frequency.
    public static func edges(bands: Int, size: Int, sampleRate: Double) -> [Int] {
        let bins = size / 2
        guard bands > 0, bins > bands, sampleRate > 0 else { return [] }
        let high = min(highest, sampleRate / 2 * 0.95)
        var edges: [Int] = []
        for index in 0...bands {
            let frequency = lowest * pow(high / lowest, Double(index) / Double(bands))
            edges.append(Int((frequency * Double(size) / sampleRate).rounded()))
        }
        edges[0] = max(edges[0], 1)
        for index in 1..<edges.count where edges[index] <= edges[index - 1] {
            edges[index] = edges[index - 1] + 1
        }
        // Pushed past the last bin by the bands below: pulled back, each one bin wide.
        if let last = edges.last, last > bins {
            for index in stride(from: edges.count - 1, through: 0, by: -1) {
                edges[index] = min(edges[index], bins - (edges.count - 1 - index))
            }
        }
        return edges
    }

    /// The height of a bar, from 0 to 1, for a band's loudness in decibels below full scale.
    public static func height(decibels: Double, band: Int, of bands: Int) -> Double {
        guard decibels.isFinite else { return 0 }
        let lifted = decibels + tilt * Double(band) / Double(max(bands - 1, 1))
        return min(max((lifted - floor) / (ceiling - floor), 0), 1)
    }

    /// Bars jump up with a beat and fall back slowly, as a meter's needle does.
    public static func smoothed(_ previous: Double, toward next: Double, rise: Double = 0.65, fall: Double = 0.18) -> Double {
        previous + (next - previous) * (next > previous ? rise : fall)
    }

    /// Fewer bars from many: each takes the loudest of its group, so the beat still shows.
    public static func regroup(_ levels: [Float], into count: Int) -> [Float] {
        guard count > 0, !levels.isEmpty else { return [] }
        guard levels.count > count else { return levels + Array(repeating: levels.last ?? 0, count: count - levels.count) }
        return (0..<count).map { index in
            let start = index * levels.count / count
            let end = max(start + 1, (index + 1) * levels.count / count)
            return levels[start..<end].max() ?? 0
        }
    }
}

#if canImport(Accelerate)
import Accelerate

/// Turns a stream of samples into the levels of a few frequency bands, about thirty times a second. Every buffer is
/// made once: feeding it samples and reading levels allocates nothing, so it can run on the audio thread.
public final class SpectrumAnalyzer {
    public let bands: Int
    public let sampleRate: Double
    /// Samples between two analyses.
    public let hop: Int
    public let size: Int

    private let fft: vDSP.FFT<DSPSplitComplex>
    private let edges: [Int]
    private let window: UnsafeMutablePointer<Float>
    private let ring: UnsafeMutablePointer<Float>
    private let frame: UnsafeMutablePointer<Float>
    private let real: UnsafeMutablePointer<Float>
    private let imaginary: UnsafeMutablePointer<Float>
    private let magnitudes: UnsafeMutablePointer<Float>
    private var write = 0
    private var sinceLast = 0
    /// The bars as they stand, smoothed.
    public private(set) var levels: [Float]

    /// `bands` from 4 to 24, `rate` analyses a second.
    public init?(bands: Int, sampleRate: Double, rate: Double = 30) {
        guard (1...64).contains(bands), sampleRate >= 8000, sampleRate <= 384_000, rate > 0 else { return nil }
        // About 43 ms of sound at 48 kHz: fine enough for the bass, quick enough for the beat.
        let size = sampleRate > 50_000 ? 4096 : 2048
        guard let fft = vDSP.FFT(log2n: vDSP_Length(log2(Double(size))), radix: .radix2, ofType: DSPSplitComplex.self) else { return nil }
        self.bands = bands
        self.sampleRate = sampleRate
        self.size = size
        self.fft = fft
        hop = max(1, Int(sampleRate / rate))
        edges = SpectrumBands.edges(bands: bands, size: size, sampleRate: sampleRate)
        window = .allocate(capacity: size)
        ring = .allocate(capacity: size)
        frame = .allocate(capacity: size)
        real = .allocate(capacity: size / 2)
        imaginary = .allocate(capacity: size / 2)
        magnitudes = .allocate(capacity: size / 2)
        vDSP_hann_window(window, vDSP_Length(size), Int32(vDSP_HANN_DENORM))
        ring.initialize(repeating: 0, count: size)
        frame.initialize(repeating: 0, count: size)
        real.initialize(repeating: 0, count: size / 2)
        imaginary.initialize(repeating: 0, count: size / 2)
        magnitudes.initialize(repeating: 0, count: size / 2)
        levels = Array(repeating: 0, count: bands)
    }

    deinit {
        for pointer in [window, ring, frame, real, imaginary, magnitudes] { pointer.deallocate() }
    }

    /// Adds mono samples. True when enough have come for new levels: then call `analyze()`.
    public func append(_ samples: UnsafePointer<Float>, count: Int) -> Bool {
        var remaining = count
        var source = samples
        while remaining > 0 {
            let chunk = min(remaining, size - write)
            (ring + write).update(from: source, count: chunk)
            write = (write + chunk) % size
            source += chunk
            remaining -= chunk
        }
        sinceLast += count
        guard sinceLast >= hop else { return false }
        sinceLast %= hop
        return true
    }

    /// Adds interleaved samples of several channels, mixed to one.
    public func append(interleaved samples: UnsafePointer<Float>, frames: Int, channels: Int) -> Bool {
        guard channels > 1 else { return append(samples, count: frames) }
        var due = false
        var done = 0
        // Mixed through `frame`, which is free between analyses, a part at a time.
        while done < frames {
            let chunk = min(frames - done, size)
            var gain = 1 / Float(channels)
            for channel in 0..<channels {
                let start = samples + done * channels + channel
                if channel == 0 {
                    vDSP_vsmul(start, vDSP_Stride(channels), &gain, frame, 1, vDSP_Length(chunk))
                } else {
                    vDSP_vsma(start, vDSP_Stride(channels), &gain, frame, 1, frame, 1, vDSP_Length(chunk))
                }
            }
            due = append(frame, count: chunk) || due
            done += chunk
        }
        return due
    }

    /// The levels of the last `size` samples, from 0 to 1 per band, smoothed with the previous ones.
    @discardableResult
    public func analyze() -> [Float] {
        // The ring, oldest sample first, through the window.
        let older = size - write
        frame.update(from: ring + write, count: older)
        (frame + older).update(from: ring, count: write)
        vDSP_vmul(frame, 1, window, 1, frame, 1, vDSP_Length(size))

        var split = DSPSplitComplex(realp: real, imagp: imaginary)
        frame.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) { complex in
            vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(size / 2))
        }
        let input = split
        fft.forward(input: input, output: &split)
        vDSP_zvabs(&split, 1, magnitudes, 1, vDSP_Length(size / 2))
        // A full-scale sine reads 1: the transform sums `size` samples and doubles them, the window halves them.
        var scale = Float(2) / Float(size)
        vDSP_vsmul(magnitudes, 1, &scale, magnitudes, 1, vDSP_Length(size / 2))

        for band in 0..<min(bands, edges.count - 1) {
            let start = edges[band], end = max(edges[band] + 1, edges[band + 1])
            var power: Float = 0
            vDSP_svesq(magnitudes + start, 1, &power, vDSP_Length(end - start))
            // The band's whole energy: with bands an equal number of octaves wide, pink noise reads even.
            let amplitude = sqrt(power)
            let decibels = amplitude > 0 ? 20 * log10(Double(amplitude)) : -.infinity
            let height = SpectrumBands.height(decibels: decibels, band: band, of: bands)
            levels[band] = Float(SpectrumBands.smoothed(Double(levels[band]), toward: height))
        }
        return levels
    }

    /// Back to silence, as when the music stops.
    public func reset() {
        ring.update(repeating: 0, count: size)
        write = 0
        sinceLast = 0
        for index in levels.indices { levels[index] = 0 }
    }
}
#endif
