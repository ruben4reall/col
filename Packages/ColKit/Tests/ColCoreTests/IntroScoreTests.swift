import CoreGraphics
import Testing
@testable import ColCore

struct IntroScoreTests {
    let notch = IslandLayout(notch: NotchMetrics(width: 188, height: 32, centerX: 756, isHardware: true))
    let pill = IslandLayout(notch: NotchMetrics(width: 72, height: 24, centerX: 756, isHardware: false), floating: .pill)
    let below = IslandLayout(notch: NotchMetrics(width: 180, height: 24, centerX: 756, isHardware: false), floating: .below)

    private func segments(_ path: CGPath) -> [CGPathElementType] {
        var types: [CGPathElementType] = []
        path.applyWithBlock { types.append($0.pointee.type) }
        return types
    }

    @Test func theScoreRunsInOrder() {
        #expect(IntroScore.traceStart < IntroScore.traceEnd)
        #expect(IntroScore.traceEnd <= IntroScore.bells[0])
        #expect(IntroScore.bells == IntroScore.bells.sorted())
        #expect(IntroScore.swell == IntroScore.bells[0])
        #expect(IntroScore.bells.last! + IntroScore.waveDuration < IntroScore.end + 0.5)
        #expect(IntroScore.tuck < IntroScore.end)
        #expect(IntroScore.end < IntroScore.soundDuration)
    }

    @Test(arguments: [0, 1, 2, 3])
    func barsStayBetweenRestAndFull(bar: Int) {
        for step in 0...300 {
            let level = IntroScore.barLevel(bar, at: Double(step) / 100)
            #expect(level >= IntroScore.barRest - 0.0001 && level <= 1.0001)
        }
        #expect(IntroScore.barLevel(bar, at: 0) == IntroScore.barRest)
    }

    @Test func eachBellLiftsTheBarsNearestItsPitch() {
        // Just after the first, lowest bell, the left bar stands higher than the right one; after the last, highest
        // one, the reverse.
        let first = IntroScore.bells[0] + 0.04
        #expect(IntroScore.barLevel(0, at: first) > IntroScore.barLevel(3, at: first))
        let last = IntroScore.bells[3] + 0.04
        #expect(IntroScore.barLevel(3, at: last) > IntroScore.barLevel(0, at: last))
        // A bell lifts its bar above where it stood just before it.
        for (index, bell) in IntroScore.bells.enumerated() {
            #expect(IntroScore.barLevel(index, at: bell + 0.03) > IntroScore.barLevel(index, at: bell - 0.01))
        }
    }

    @Test func barKeyframesCoverTheSwellToTheTuck() {
        let frames = IntroScore.barKeyframes(1, rate: 30)
        #expect(frames.count == Int(((IntroScore.tuck - IntroScore.swell) * 30).rounded()) + 1)
        #expect(frames.first! == IntroScore.barLevel(1, at: IntroScore.swell))
        // Back near rest as the island tucks in.
        #expect(frames.last! < 0.4)
    }

    @Test func aWaveStartsOnTheIslandAndGrowsOutward() {
        for layout in [notch, pill, below] {
            let shape = layout.shape(for: .collapsed, wings: Wings(32))
            let start = IntroGeometry.wave(from: shape, progress: 0)
            #expect(start == shape)
            var previous = start
            for step in 1...10 {
                let wave = IntroGeometry.wave(from: shape, progress: CGFloat(step) / 10)
                #expect(wave.width > previous.width)
                #expect(wave.height > previous.height)
                previous = wave
            }
            #expect(abs(previous.width - shape.width - IntroScore.waveReach.width * 2) < 0.001)
        }
    }

    @Test func wavesMorphWithTheSameSegmentsAllTheWayOut() {
        for layout in [notch, pill, below] {
            let shape = layout.shape(for: .collapsed, wings: Wings(32))
            let floating = shape.isFloating
            let near = segments(IntroGeometry.path(shape, centerX: 400, floating: floating))
            let far = segments(IntroGeometry.path(IntroGeometry.wave(from: shape, progress: 1), centerX: 400, floating: floating))
            #expect(near == far)
            // The island at rest morphs into the swollen island too.
            let rest = segments(IntroGeometry.path(layout.shape(for: .collapsed), centerX: 400, floating: floating))
            #expect(rest == near)
        }
    }

    @Test func aFloatingWaveGrowsPastTheTopEdge() {
        let shape = pill.shape(for: .collapsed, wings: Wings(32))
        let wave = IntroGeometry.wave(from: shape, progress: 1)
        #expect(wave.gap < 0)
        let box = IntroGeometry.path(wave, centerX: 400, floating: true).boundingBoxOfPath
        #expect(box.minY < 0)
        #expect(abs(box.height - wave.height) < 0.001)
    }

    @Test func theLightRunsFromTheTopToTheMiddleOfTheLowerEdge() {
        for layout in [notch, pill] {
            let shape = layout.shape(for: .collapsed)
            let halves = IntroGeometry.traceHalves(shape, centerX: 400)
            for (path, side) in [(halves.left, -1.0), (halves.right, 1.0)] {
                var points: [CGPoint] = []
                path.applyWithBlock { element in
                    let count = switch element.pointee.type {
                    case .moveToPoint, .addLineToPoint: 1
                    case .addQuadCurveToPoint: 2
                    case .addCurveToPoint: 3
                    default: 0
                    }
                    if count > 0 { points.append(element.pointee.points[count - 1]) }
                }
                let first = points.first!, last = points.last!
                // Ends in the middle of the lower edge.
                #expect(abs(last.x - 400) < 0.001)
                #expect(abs(last.y - (shape.gap + shape.height)) < 0.001)
                // Starts at the top: an upper corner on its own side, or the top centre of a floating island.
                #expect(abs(first.y - shape.gap) < 0.001)
                if shape.isFloating {
                    #expect(abs(first.x - 400) < 0.001)
                } else {
                    #expect((first.x - 400) * side > shape.width / 2 - 0.001)
                }
                // Each half stays on its side.
                let box = path.boundingBoxOfPath
                #expect(side < 0 ? box.maxX <= 400.001 : box.minX >= 399.999)
            }
        }
    }
}
