import CoreGraphics
import Testing
@testable import ColCore

struct IslandGeometryTests {
    let layout = IslandLayout(notch: NotchMetrics(width: 188, height: 32, centerX: 756, isHardware: true))

    @Test(arguments: [IslandState.collapsed, .peek, .expanded])
    func pathFillsItsShapeExactly(state: IslandState) {
        let shape = layout.shape(for: state)
        let box = IslandPath.make(shape, centerX: 300).boundingBoxOfPath
        #expect(abs(box.minX - (300 - shape.outerWidth / 2)) < 0.001)
        #expect(abs(box.width - shape.outerWidth) < 0.001)
        #expect(abs(box.minY) < 0.001)
        #expect(abs(box.height - shape.height) < 0.001)
    }

    @Test func everyStateMorphsWithTheSameSegments() {
        func segments(_ state: IslandState) -> [CGPathElementType] {
            var types: [CGPathElementType] = []
            IslandPath.make(layout.shape(for: state), centerX: 0).applyWithBlock { types.append($0.pointee.type) }
            return types
        }
        #expect(segments(.collapsed) == segments(.expanded))
        #expect(segments(.peek) == segments(.expanded))
    }

    @Test func extremeRadiiStayInsideTheBody() {
        let tiny = IslandShape(width: 20, height: 10, earRadius: 40, cornerRadius: 90)
        let box = IslandPath.make(tiny, centerX: 0).boundingBoxOfPath
        #expect(box.height <= 10.001)
        #expect(box.maxY >= 9.999)
    }

    @Test func statesGrowInOrder() {
        let sizes = [IslandState.collapsed, .peek, .expanded].map { layout.shape(for: $0) }
        #expect(sizes[0].width < sizes[1].width && sizes[1].width < sizes[2].width)
        #expect(sizes[0].height < sizes[1].height && sizes[1].height < sizes[2].height)
    }

    @Test func collapsedWindowHugsTheNotch() {
        let size = layout.windowSize(for: .collapsed)
        #expect(size.height == 32)
        #expect(size.width == CGFloat(188 + 8))
    }

    @Test func canvasHoldsEveryStateAndTheContent() {
        let canvas = CGRect(origin: .zero, size: layout.canvasSize)
        for state in [IslandState.collapsed, .peek, .expanded] {
            #expect(canvas.contains(layout.frame(for: state)))
        }
        #expect(layout.frame(for: .expanded).contains(layout.contentFrame))
        #expect(layout.contentFrame.minY == 0)
        #expect(layout.contentFrame.width == layout.shape(for: .expanded).width)
    }

    @Test func wideNotchesStillLeaveRoomAroundTheCamera() {
        let wide = IslandLayout(notch: NotchMetrics(width: 400, height: 38, centerX: 900, isHardware: true))
        #expect(wide.shape(for: .expanded).width == 560)
    }
}

struct IslandWingTests {
    let layout = IslandLayout(notch: NotchMetrics(width: 188, height: 32, centerX: 756, isHardware: true))

    @Test func wingsWidenTheCompactIsland() {
        let plain = layout.shape(for: .collapsed)
        let winged = layout.shape(for: .collapsed, wings: 40)
        #expect(winged.width - plain.width == CGFloat(80))
        #expect(winged.height == plain.height)
    }

    @Test func wingsAreCapped() {
        let capped = layout.shape(for: .collapsed, wings: 1_000)
        #expect(capped.width == 188 + IslandLayout.maximumWing * 2)
        #expect(CGRect(origin: .zero, size: layout.canvasSize).contains(layout.frame(for: .peek, wings: 1_000)))
    }

    @Test func wingItemsSitBesideTheCamera() {
        let left = layout.wingCenter(leading: true, wings: 40)
        let right = layout.wingCenter(leading: false, wings: 40)
        #expect(abs((left.x + right.x) / 2 - layout.canvasSize.width / 2) < 0.001)
        #expect(right.x - left.x == CGFloat(228))
        #expect(left.y == 16)
    }

    @Test func openIslandIgnoresWings() {
        #expect(layout.shape(for: .expanded, wings: 50) == layout.shape(for: .expanded))
    }
}

struct IslandSizeTests {
    let notch = NotchMetrics(width: 188, height: 32, centerX: 756, isHardware: true)

    @Test func sizesGrowInOrder() {
        let widths = IslandSize.allCases.map { IslandLayout(notch: notch, size: $0).shape(for: .expanded).width }
        #expect(widths == widths.sorted())
        #expect(Set(widths).count == 3)
    }

    @Test func theCanvasFollowsTheSize() {
        let large = IslandLayout(notch: notch, size: .large)
        let canvas = CGRect(origin: .zero, size: large.canvasSize)
        #expect(canvas.contains(large.frame(for: .expanded)))
        #expect(large.contentFrame.width == CGFloat(540))
    }

    @Test func compactStillClearsTheCamera() {
        let wide = NotchMetrics(width: 320, height: 38, centerX: 800, isHardware: true)
        #expect(IslandLayout(notch: wide, size: .compact).shape(for: .expanded).width == CGFloat(480))
    }
}

struct FloatingIslandTests {
    let layout = IslandLayout(notch: NotchMetrics(width: 180, height: 25, centerX: 1280, isHardware: false))

    @Test func floatsBelowTheMenuBar() {
        let closed = layout.shape(for: .collapsed)
        #expect(closed.isFloating)
        #expect(closed.gap == CGFloat(31))
        #expect(closed.earRadius == 0)
        #expect(closed.cornerRadius == closed.height / 2)
    }

    @Test func pathStaysInItsFrame() {
        for state in [IslandState.collapsed, .peek, .expanded] {
            let shape = layout.shape(for: state, wings: 30)
            let box = IslandPath.make(shape, centerX: 400).boundingBoxOfPath
            #expect(abs(box.minY - shape.gap) < 0.001)
            #expect(abs(box.height - shape.height) < 0.001)
            #expect(abs(box.width - shape.width) < 0.001)
        }
    }

    @Test func morphsWithTheSameSegments() {
        func kinds(_ state: IslandState) -> [CGPathElementType] {
            var list: [CGPathElementType] = []
            IslandPath.make(layout.shape(for: state), centerX: 0).applyWithBlock { list.append($0.pointee.type) }
            return list
        }
        #expect(kinds(.collapsed) == kinds(.expanded))
    }

    @Test func windowAndContentFollowTheGap() {
        #expect(layout.windowSize(for: .collapsed).height == CGFloat(31 + 34))
        #expect(layout.contentFrame.minY == CGFloat(31))
        #expect(layout.wingCenter(leading: true, wings: 20).y == CGFloat(31 + 17))
        let canvas = CGRect(origin: .zero, size: layout.canvasSize)
        #expect(canvas.contains(layout.frame(for: .expanded)))
    }

    @Test func theHardwareNotchStillHangs() {
        let notched = IslandLayout(notch: NotchMetrics(width: 188, height: 32, centerX: 756, isHardware: true))
        #expect(notched.shape(for: .collapsed).gap == 0)
    }

@Suite struct OneSidedWingTests {
    let layout = IslandLayout(notch: NotchMetrics(width: 190, height: 32, centerX: 756, isHardware: true))

    @Test func aSingleWingPullsTheBodyToItsSide() {
        let shape = layout.shape(for: .collapsed, wings: Wings(leading: 0, trailing: 60))
        #expect(shape.width == CGFloat(190 + 60))
        #expect(shape.offset == CGFloat(30))
        // The body starts exactly at the notch's left edge and ends 60 points past its right edge.
        let frame = layout.frame(for: .collapsed, wings: Wings(leading: 0, trailing: 60))
        let notchLeft = layout.canvasSize.width / 2 - 95
        #expect(abs(frame.minX + shape.earRadius - notchLeft) < 0.001)
    }

    @Test func theWindowStaysCentredAndCoversTheShape() {
        let wings = Wings(leading: 0, trailing: 60)
        let window = layout.windowSize(for: .collapsed, wings: wings)
        let frame = layout.frame(for: .collapsed, wings: wings)
        let windowMinX = (layout.canvasSize.width - window.width) / 2
        #expect(frame.minX >= windowMinX - 0.001)
        #expect(frame.maxX <= windowMinX + window.width + 0.001)
    }

    @Test func aSingleWingShowsTheValue() {
        let music = CompactPresentation(leading: .symbol("music.note", tint: .white), trailing: .equalizer(tint: .white, playing: true))
        #expect(music.fitted(to: Wings(leading: 0, trailing: 40)) == CompactPresentation(trailing: .equalizer(tint: .white, playing: true)))
        #expect(music.fitted(to: Wings(leading: 40, trailing: 0)) == CompactPresentation(leading: .equalizer(tint: .white, playing: true)))
        #expect(music.fitted(to: Wings(40)) == music)
        #expect(music.fitted(to: .none) == nil)
        let alone = CompactPresentation(leading: .symbol("mic.fill", tint: .orange))
        #expect(alone.fitted(to: Wings(leading: 0, trailing: 40)) == CompactPresentation(trailing: .symbol("mic.fill", tint: .orange)))
    }
}

}

