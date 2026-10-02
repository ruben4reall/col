import Testing
@testable import ColCore

struct IslandMachineTests {
    @Test func hoverPeeksThenOpens() {
        var machine = IslandMachine()
        #expect(machine.handle(.pointerEntered) == [.startHoverTimer])
        #expect(machine.state == .peek)
        #expect(machine.handle(.hoverTimerFired) == [.haptic])
        #expect(machine.state == .expanded)
    }

    @Test func leavingBeforeTheDwellOnlyPeeks() {
        var machine = IslandMachine()
        _ = machine.handle(.pointerEntered)
        #expect(machine.handle(.pointerExited) == [.cancelHoverTimer])
        #expect(machine.state == .collapsed)
        // A timer that fires anyway, late, changes nothing.
        #expect(machine.handle(.hoverTimerFired) == [])
        #expect(machine.state == .collapsed)
    }

    @Test func withoutHoverOpeningOnlyAClickOpens() {
        var machine = IslandMachine(opensOnHover: false)
        #expect(machine.handle(.pointerEntered) == [])
        #expect(machine.state == .peek)
        #expect(machine.handle(.pressed) == [.cancelHoverTimer, .haptic])
        #expect(machine.state == .expanded)
    }

    @Test func swipeDownOpensFromTheNotch() {
        var machine = IslandMachine()
        _ = machine.handle(.pointerEntered)
        _ = machine.handle(.swipedDown)
        #expect(machine.state == .expanded)
    }

    @Test func slippingOffTheEdgeIsForgiven() {
        var machine = IslandMachine()
        _ = machine.handle(.pressed)
        #expect(machine.handle(.pointerExited) == [.startExitTimer])
        #expect(machine.handle(.pointerEntered) == [.cancelExitTimer])
        // The cancelled timer fires late: the pointer is back, so the island stays open.
        #expect(machine.handle(.exitTimerFired) == [])
        #expect(machine.state == .expanded)
    }

    @Test func leavingForGoodCloses() {
        var machine = IslandMachine()
        _ = machine.handle(.pointerEntered)
        _ = machine.handle(.hoverTimerFired)
        _ = machine.handle(.pointerExited)
        _ = machine.handle(.exitTimerFired)
        #expect(machine.state == .collapsed)
    }

    @Test func swipeUpClosesAtOnceAndDoesNotReopen() {
        var machine = IslandMachine()
        _ = machine.handle(.pointerEntered)
        _ = machine.handle(.hoverTimerFired)
        #expect(machine.handle(.swipedUp) == [.cancelHoverTimer, .cancelExitTimer])
        #expect(machine.state == .collapsed)
        // Still resting on the notch: nothing reopens until the pointer leaves and comes back.
        #expect(machine.handle(.hoverTimerFired) == [])
        #expect(machine.state == .collapsed)
    }

    @Test func pressingTheOpenIslandIsLeftToItsContent() {
        var machine = IslandMachine()
        _ = machine.handle(.pressed)
        #expect(machine.handle(.pressed) == [])
        #expect(machine.handle(.swipedDown) == [])
    }

    @Test func aRequestOpensTheIslandAndKeepsItOpen() {
        var machine = IslandMachine()
        #expect(machine.handle(.requested) == [.cancelHoverTimer, .haptic])
        #expect(machine.state == .expanded)
        // Visiting and leaving closes it like any open island.
        _ = machine.handle(.pointerEntered)
        #expect(machine.handle(.pointerExited) == [.startExitTimer])
        _ = machine.handle(.dismissed)
        #expect(machine.state == .collapsed)
    }
}
