// scripts/make-intro-sound.swift: writes the chime Col plays as it opens, from code alone: no sample, no recording, so
// the sound is the project's own and MIT like the rest of it.
//
// A rising arpeggio of glass bells (D, A, E, F sharp: an open D major) over a soft chord, a breath of air before it
// and a few sparkles after, in a small room. Each bell sends one of the intro's waves out of the notch: the times
// below are IntroScore's (Packages/ColKit/Sources/ColCore/IntroScore.swift), and Windows and Linux use the same.
//
//   swift scripts/make-intro-sound.swift OUT.wav
//
// scripts/make-intro-sound.sh turns it into what each system bundles.
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "intro.wav")
let rate = 48_000.0
let duration = 2.9
let frames = Int(duration * rate)

// MARK: The score

/// The light runs around the notch until the first bell.
let breathEnd = 0.42
/// The four bells, a hundred and fifty milliseconds apart.
struct Bell { let time, frequency, gain, pan, decay: Double }
let bells = [
    Bell(time: 0.42, frequency: 587.33, gain: 0.82, pan: -0.28, decay: 0.55), // D5
    Bell(time: 0.57, frequency: 880.00, gain: 0.70, pan: 0.28, decay: 0.55), // A5
    Bell(time: 0.72, frequency: 1318.51, gain: 0.58, pan: -0.12, decay: 0.62), // E6
    Bell(time: 0.87, frequency: 1479.98, gain: 0.66, pan: 0.14, decay: 1.0), // F#6, the one that rings on
]
/// Sparkles after the last bell, far up and spread wide.
let sparkles = [
    Bell(time: 0.94, frequency: 2637.02, gain: 0.07, pan: 0.55, decay: 0.14), // E7
    Bell(time: 1.06, frequency: 2959.96, gain: 0.06, pan: -0.5, decay: 0.14), // F#7
    Bell(time: 1.20, frequency: 3520.00, gain: 0.05, pan: 0.3, decay: 0.16), // A7
]
/// The chord under the bells: D4, F#4, A4, and E5 faintly.
let chord: [(frequency: Double, gain: Double)] = [(293.66, 1), (369.99, 0.8), (440.0, 0.75), (659.26, 0.3)]

// MARK: Voices

let tau = 2 * Double.pi

/// A glass bell: frequency modulation whose brightness falls fast, a short inharmonic strike, an octave below for
/// warmth.
func bell(_ t: Double, _ f: Double, decay: Double) -> Double {
    guard t >= 0 else { return 0 }
    let attack = min(1, t / 0.003)
    let envelope = attack * exp(-t / decay)
    let index = 1.2 * exp(-t / 0.10) + 0.08
    let body = sin(tau * f * t + index * sin(tau * f * 2 * t))
    let strike = 0.10 * exp(-t / 0.05) * sin(tau * f * 2.76 * t)
    let under = 0.18 * exp(-t / (decay * 0.8)) * sin(tau * f * 0.5 * t)
    return envelope * (body + strike + under)
}

/// A plain sine ping, for the sparkles.
func ping(_ t: Double, _ f: Double, decay: Double) -> Double {
    guard t >= 0 else { return 0 }
    return min(1, t / 0.002) * exp(-t / decay) * sin(tau * f * t)
}

func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

/// The chord swells in with the first bell, holds, and lets go as the island tucks back.
func pad(_ t: Double, detune: Double) -> Double {
    let swell = smoothstep(0.40, 0.95, t) * (1 - smoothstep(1.55, 2.75, t))
    guard swell > 0 else { return 0 }
    var sum = 0.0
    for note in chord {
        let f = note.frequency * detune
        sum += note.gain * (sin(tau * f * t) + 0.22 * sin(tau * 2 * f * t))
    }
    return swell * sum
}

/// Deterministic noise, so every build writes the same file.
struct Noise {
    var state: UInt64
    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 2_000_001) / 1_000_000 - 1
    }
}

/// A state-variable band-pass, for the breath of air.
struct BandPass {
    var low = 0.0, band = 0.0
    mutating func process(_ x: Double, frequency: Double, q: Double) -> Double {
        let f = 2 * sin(Double.pi * min(frequency, rate / 6) / rate)
        let high = x - low - band / q
        band += f * high
        low += f * band
        return band
    }
}

// MARK: Dry mix

var left = [Double](repeating: 0, count: frames)
var right = [Double](repeating: 0, count: frames)
var noiseL = Noise(state: 0x9E37_79B9_7F4A_7C15), noiseR = Noise(state: 0xD1B5_4A32_D192_ED03)
var airL = BandPass(), airR = BandPass()
var thumpPhase = 0.0

for i in 0..<frames {
    let t = Double(i) / rate
    var l = 0.0, r = 0.0

    // A breath of air rising toward the first bell, as the light runs around the notch.
    if t < breathEnd + 0.08 {
        let rise = smoothstep(0.02, breathEnd - 0.06, t) * (1 - smoothstep(breathEnd - 0.04, breathEnd + 0.06, t))
        let center = 350 * pow(3800 / 350, smoothstep(0.02, breathEnd, t))
        l += 0.10 * rise * airL.process(noiseL.next(), frequency: center, q: 0.9)
        r += 0.10 * rise * airR.process(noiseR.next(), frequency: center * 1.06, q: 0.9)
    }

    // The bells, each placed in the stereo field with equal power.
    for b in bells {
        let v = b.gain * bell(t - b.time, b.frequency, decay: b.decay)
        let angle = (b.pan + 1) * Double.pi / 4
        l += v * cos(angle)
        r += v * sin(angle)
    }
    for s in sparkles {
        let v = s.gain * ping(t - s.time, s.frequency, decay: s.decay)
        let angle = (s.pan + 1) * Double.pi / 4
        l += v * cos(angle)
        r += v * sin(angle)
    }

    // A warm low note under the first bell, its pitch settling as it lands.
    let since = t - bells[0].time
    if since >= 0 {
        let frequency = 146.83 * (1 + 0.25 * exp(-since / 0.03))
        thumpPhase += tau * frequency / rate
        let envelope = (1 - exp(-since / 0.006)) * exp(-since / 0.16)
        let v = 0.2 * envelope * (sin(thumpPhase) + 0.3 * sin(2 * thumpPhase))
        l += v
        r += v
    }

    // The chord, a touch apart in each ear.
    l += 0.055 * pad(t, detune: 0.9992)
    r += 0.055 * pad(t, detune: 1.0008)

    left[i] = l
    right[i] = r
}

// MARK: Room

/// A small stereo room: four damped combs and two all-passes per side (Schroeder and Moorer's design).
struct Comb {
    var buffer: [Double]
    var index = 0
    var store = 0.0
    let feedback: Double, damping: Double
    init(_ length: Int, feedback: Double, damping: Double) {
        buffer = [Double](repeating: 0, count: length)
        self.feedback = feedback
        self.damping = damping
    }
    mutating func process(_ x: Double) -> Double {
        let y = buffer[index]
        store = y * (1 - damping) + store * damping
        buffer[index] = x + store * feedback
        index = (index + 1) % buffer.count
        return y
    }
}

struct AllPass {
    var buffer: [Double]
    var index = 0
    init(_ length: Int) { buffer = [Double](repeating: 0, count: length) }
    mutating func process(_ x: Double) -> Double {
        let delayed = buffer[index]
        let y = -x + delayed
        buffer[index] = x + delayed * 0.5
        index = (index + 1) % buffer.count
        return y
    }
}

func room(spread: Int) -> (combs: [Comb], allPasses: [AllPass]) {
    let scale = rate / 44_100
    let combs = [1557, 1617, 1491, 1422].map { Comb(Int(Double($0 + spread) * scale), feedback: 0.80, damping: 0.28) }
    let allPasses = [556, 441].map { AllPass(Int(Double($0 + spread) * scale)) }
    return (combs, allPasses)
}

var roomL = room(spread: 0), roomR = room(spread: 23)
let predelay = Int(0.012 * rate)
var wetL = [Double](repeating: 0, count: frames)
var wetR = [Double](repeating: 0, count: frames)
for i in 0..<frames {
    let source = i >= predelay ? (left[i - predelay] + right[i - predelay]) * 0.5 : 0
    var l = 0.0, r = 0.0
    for c in roomL.combs.indices { l += roomL.combs[c].process(source * 0.25) }
    for c in roomR.combs.indices { r += roomR.combs[c].process(source * 0.25) }
    for a in roomL.allPasses.indices { l = roomL.allPasses[a].process(l) }
    for a in roomR.allPasses.indices { r = roomR.allPasses[a].process(r) }
    wetL[i] = l
    wetR[i] = r
}

// MARK: Master

var mixL = [Double](repeating: 0, count: frames)
var mixR = [Double](repeating: 0, count: frames)
// A gentle high-pass at 60 Hz keeps small speakers clean.
let hp = exp(-tau * 60 / rate)
var hpInL = 0.0, hpOutL = 0.0, hpInR = 0.0, hpOutR = 0.0
let fadeOut = 0.32
for i in 0..<frames {
    let t = Double(i) / rate
    var l = left[i] + 0.34 * wetL[i]
    var r = right[i] + 0.34 * wetR[i]
    let outL = hp * (hpOutL + l - hpInL); hpInL = l; hpOutL = outL; l = outL
    let outR = hp * (hpOutR + r - hpInR); hpInR = r; hpOutR = outR; r = outR
    let tail = t > duration - fadeOut ? 0.5 * (1 + cos(Double.pi * (t - (duration - fadeOut)) / fadeOut)) : 1
    let head = min(1, t / 0.005)
    mixL[i] = l * tail * head
    mixR[i] = r * tail * head
}

// Peaks at -3 dBFS, by gain alone: nothing saturates, so the bells keep their glass.
let peak = max(mixL.map(abs).max() ?? 1, mixR.map(abs).max() ?? 1)
let gain = 0.708 / peak
for i in 0..<frames {
    mixL[i] *= gain
    mixR[i] *= gain
}

// MARK: Report and write

func dB(_ x: Double) -> String { x > 0 ? String(format: "%6.1f dB", 20 * log10(x)) : "  -inf dB" }
let window = Int(0.1 * rate)
var report = "time    rms\n"
for start in stride(from: 0, to: frames, by: window) {
    let end = min(start + window, frames)
    var sum = 0.0
    for i in start..<end { sum += (mixL[i] * mixL[i] + mixR[i] * mixR[i]) / 2 }
    report += String(format: "%4.1f s ", Double(start) / rate) + dB(sqrt(sum / Double(end - start))) + "\n"
}
var total = 0.0
for i in 0..<frames { total += (mixL[i] * mixL[i] + mixR[i] * mixR[i]) / 2 }
report += "overall " + dB(sqrt(total / Double(frames))) + ", peak -3.0 dB\n"
FileHandle.standardError.write(report.data(using: .utf8)!)

var data = Data()
func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
let channels: UInt16 = 2, bits: UInt16 = 16
let byteRate = UInt32(rate) * UInt32(channels) * UInt32(bits / 8)
data.append("RIFF".data(using: .ascii)!)
append(UInt32(36 + frames * Int(channels) * 2))
data.append("WAVEfmt ".data(using: .ascii)!)
append(UInt32(16)); append(UInt16(1)); append(channels); append(UInt32(rate)); append(byteRate)
append(UInt16(channels * bits / 8)); append(bits)
data.append("data".data(using: .ascii)!)
append(UInt32(frames * Int(channels) * 2))
for i in 0..<frames {
    // Triangular dither before rounding to 16 bits.
    let d1 = noiseL.next() * 0.5 / 32768, d2 = noiseR.next() * 0.5 / 32768
    append(Int16(max(-32767, min(32767, ((mixL[i] + d1) * 32767).rounded()))))
    append(Int16(max(-32767, min(32767, ((mixR[i] + d2) * 32767).rounded()))))
}
try data.write(to: output)
