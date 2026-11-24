import CoreGraphics
import Foundation

/// The intro Col plays as it opens, written as a score: light runs around the island, the island swells out of the
/// notch on the first bell of a rising chime, each bell sends a wave out of it, then it tucks back in as the chord lets
/// go. The chime is written to these very times (scripts/make-intro-sound.swift), and Col on Windows and Linux plays
/// the same score.
public enum IntroScore {
    /// The light runs from the island's upper corners down to the middle of its lower edge, as air rises in the chime.
    public static let traceStart = 0.05
    public static let traceEnd = 0.42
    /// The four bells, a hundred and fifty milliseconds apart, lowest first. Each one sends a wave.
    public static let bells = [0.42, 0.57, 0.72, 0.87]
    /// The island swells out of the notch with the first bell...
    public static let swell = 0.42
    /// ...and tucks back in as the chord lets go.
    public static let tuck = 1.85
    /// Everything has settled: the island is itself again.
    public static let end = 2.45
    /// The chime lasts a little longer than the picture: its last bell rings on.
    public static let soundDuration = 2.9
    /// A wave travels this long, fading as it goes.
    public static let waveDuration = 1.3
    /// How far a wave travels from the island: sideways on each side, and downward.
    public static let waveReach = CGSize(width: 150, height: 96)

    /// Where the bars of the intro's equalizer rest, as a share of their full height: the dots of a paused song.
    public static let barRest = 0.22

    /// How high bar `bar` (0 to 3, left to right) stands at `time`, from `barRest` to 1. Each bell lifts the bars
    /// nearest its pitch, the low ones on the left, and they fall back as it fades; the chord keeps them breathing
    /// until the island tucks in.
    public static func barLevel(_ bar: Int, at time: Double) -> Double {
        var lift = 0.0
        for (index, bell) in bells.enumerated() {
            let since = time - bell
            guard since >= 0 else { continue }
            let attack = min(1, since / 0.03)
            // The last bell rings on, as in the chime.
            let decay = index == bells.count - 1 ? 0.55 : 0.26
            let nearness = exp(-pow(Double(bar - index), 2) / 1.4)
            lift += attack * exp(-since / decay) * nearness
        }
        let chord = smoothstep(swell, swell + 0.5, time) * (1 - smoothstep(tuck - 0.35, tuck, time))
        lift += 0.16 * chord * (0.75 + 0.25 * sin(time * 9 + Double(bar) * 1.7))
        return barRest + (1 - barRest) * min(1, lift)
    }

    /// The bars' heights from the swell to the tuck, `rate` a second, for a keyframe animation the render server plays.
    public static func barKeyframes(_ bar: Int, rate: Double = 30) -> [Double] {
        let count = Int(((tuck - swell) * rate).rounded()) + 1
        return (0..<count).map { barLevel(bar, at: swell + Double($0) / rate) }
    }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// The intro's shapes, in the island canvas's top-left space.
public enum IntroGeometry {
    /// The outline a wave has at `progress`: the island's own (0) to the farthest it reaches (1). A wave keeps the
    /// island's kind of outline, hanging from the top edge or floating, so every step morphs into the next.
    public static func wave(from shape: IslandShape, progress: CGFloat, reach: CGSize = IntroScore.waveReach) -> IslandShape {
        let p = min(max(progress, 0), 1)
        let dx = reach.width * p
        let dy = reach.height * p
        var wave = shape
        wave.width = shape.width + dx * 2
        if shape.isFloating {
            // A floating island grows on every side; above the top edge, the screen cuts it.
            wave.height = shape.height + dy * 2
            wave.gap = shape.gap - dy
            wave.cornerRadius = min(shape.cornerRadius + dy, wave.height / 2)
        } else {
            wave.height = shape.height + dy
            wave.earRadius = shape.earRadius + dx * 0.08
            wave.cornerRadius = shape.cornerRadius + dy * 0.55
        }
        return wave
    }

    /// The outline of a wave or of the island. Unlike `IslandPath.make`, a floating shape stays floating even when it
    /// grows past the top edge, so its path keeps the same segments all the way out.
    public static func path(_ shape: IslandShape, centerX: CGFloat, floating: Bool) -> CGPath {
        guard floating else { return IslandPath.make(shape, centerX: centerX) }
        let rect = CGRect(x: centerX - shape.width / 2, y: shape.gap, width: shape.width, height: shape.height)
        return IslandPath.rounded(rect, radius: shape.cornerRadius)
    }

    /// The two halves of the island's outline the light runs along, each from an upper corner (the top centre, for a
    /// floating island) to the middle of the lower edge: the left half, then the right one.
    public static func traceHalves(_ shape: IslandShape, centerX: CGFloat) -> (left: CGPath, right: CGPath) {
        (half(shape, centerX: centerX, side: -1), half(shape, centerX: centerX, side: 1))
    }

    /// One half of the outline, mirrored by `side` (-1 left, 1 right), with the corners `IslandPath` draws.
    private static func half(_ shape: IslandShape, centerX: CGFloat, side: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let edge = centerX + side * shape.width / 2
        if shape.isFloating {
            let top = shape.gap, bottom = shape.gap + shape.height
            let radius = min(shape.cornerRadius, shape.height / 2, shape.width / 2)
            let reach = min(radius * IslandPath.smoothing, shape.height / 2, shape.width / 2)
            let handle = reach * IslandPath.handleRatio
            path.move(to: CGPoint(x: centerX, y: top))
            path.addLine(to: CGPoint(x: edge - side * reach, y: top))
            path.addQuadCurve(to: CGPoint(x: edge, y: top + reach), control: CGPoint(x: edge, y: top))
            path.addLine(to: CGPoint(x: edge, y: bottom - reach))
            path.addCurve(to: CGPoint(x: edge - side * reach, y: bottom),
                          control1: CGPoint(x: edge, y: bottom - handle), control2: CGPoint(x: edge - side * handle, y: bottom))
            path.addLine(to: CGPoint(x: centerX, y: bottom))
            return path
        }
        let ear = max(0, min(shape.earRadius, shape.height / 3))
        let bottom = shape.height
        let reach = max(0, min(shape.cornerRadius * IslandPath.smoothing, bottom - ear, shape.width / 2))
        let handle = reach * IslandPath.handleRatio
        path.move(to: CGPoint(x: edge + side * ear, y: 0))
        path.addQuadCurve(to: CGPoint(x: edge, y: ear), control: CGPoint(x: edge, y: 0))
        path.addLine(to: CGPoint(x: edge, y: bottom - reach))
        path.addCurve(to: CGPoint(x: edge - side * reach, y: bottom),
                      control1: CGPoint(x: edge, y: bottom - handle), control2: CGPoint(x: edge - side * handle, y: bottom))
        path.addLine(to: CGPoint(x: centerX, y: bottom))
        return path
    }
}
