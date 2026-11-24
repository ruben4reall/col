using Col.Core;

namespace Col.Tests;

public class IslandGeometryTests
{
    [Fact]
    public void TheIslandFloatsBelowTheTopEdgeAsACapsule()
    {
        var layout = new IslandLayout();
        var rest = layout.Shape(IslandState.Collapsed);
        Assert.Equal((124.0, 32.0), (rest.Width, rest.Height));
        // Rounded on all four corners: a capsule.
        Assert.Equal(rest.Height / 2, rest.CornerRadius);
        Assert.Equal(IslandLayout.Gap, layout.Frame(rest).Y);
        Assert.Equal(8, IslandLayout.Gap);
    }

    [Fact]
    public void OpenIsFourHundredEightyByTwoHundredRoundedThirtyTwo()
    {
        var open = new IslandLayout().Shape(IslandState.Expanded);
        Assert.Equal(new IslandShape(480, 200, 32), open);
        Assert.Equal(440, new IslandLayout(IslandSize.Compact).Shape(IslandState.Expanded).Width);
        Assert.Equal(540, new IslandLayout(IslandSize.Large).Shape(IslandState.Expanded).Width);
    }

    [Fact]
    public void PeekingSwellsAndWingsWidenTheClosedIsland()
    {
        var layout = new IslandLayout();
        var rest = layout.Shape(IslandState.Collapsed);
        var peek = layout.Shape(IslandState.Peek);
        Assert.True(peek.Width > rest.Width && peek.Height > rest.Height);
        var music = layout.Shape(IslandState.Collapsed, new Wings(36));
        Assert.Equal(rest.Width + 72, music.Width);
        // A wing never grows past its maximum, and the middle grows for a lyric line, up to its own.
        Assert.Equal(rest.Width + 2 * IslandLayout.MaximumWing, layout.Shape(IslandState.Collapsed, new Wings(900)).Width);
        Assert.Equal(IslandLayout.MaximumMiddle, layout.Shape(IslandState.Collapsed, Wings.None, 9000).Width);
    }

    [Fact]
    public void AnIslandThatOnlyShowsWhenSomethingHappensHidesAtRest()
    {
        var layout = new IslandLayout();
        var hidden = layout.Target(IslandState.Collapsed, Wings.None, 0, visibleAtRest: false, hasActivity: false);
        Assert.Equal(0, hidden.Opacity);
        Assert.True(hidden.Width < layout.Rest.Width);
        Assert.Equal(1, layout.Target(IslandState.Collapsed, Wings.None, 0, visibleAtRest: true, hasActivity: false).Opacity);
        Assert.Equal(1, layout.Target(IslandState.Collapsed, new Wings(36), 0, visibleAtRest: false, hasActivity: true).Opacity);
        // Hovering the top edge brings it out.
        Assert.Equal(1, layout.Target(IslandState.Peek, Wings.None, 0, visibleAtRest: false, hasActivity: false).Opacity);
    }

    [Fact]
    public void TheWakeZoneIsOneRowAsWideAsThePillAndNeverTakesAButtonHeld()
    {
        var layout = new IslandLayout();
        var zone = layout.WakeZone((0, 0, 1920, 1080), 1);
        Assert.Equal(new EdgeZone(898, 1022, 0), zone);
        Assert.Equal(layout.Rest.Width, zone.Right - zone.Left);
        Assert.True(zone.Contains(960, 0, buttonHeld: false));
        Assert.True(zone.Contains(898, 0, buttonHeld: false));
        Assert.False(zone.Contains(1022, 0, buttonHeld: false));
        // One row only: a pixel lower is the window below's.
        Assert.False(zone.Contains(960, 1, buttonHeld: false));
        // Dragging a window to the top edge does not wake the island.
        Assert.False(zone.Contains(960, 0, buttonHeld: true));
        // At 150 %, on a monitor right of the first, under another one (its top is not 0).
        var second = layout.WakeZone((1920, 200, 1920 + 2560, 200 + 1440), 1.5);
        Assert.Equal(186, second.Right - second.Left);
        Assert.Equal(200, second.Top);
        Assert.Equal(1920 + 1280, (second.Left + second.Right) / 2);
        Assert.False(second.Contains(3200, 199, buttonHeld: false));
    }

    [Fact]
    public void CrossingTheGapBetweenTheEdgeAndTheIslandIsNotLeaving()
    {
        var presence = new PointerPresence();
        Assert.Equal(PointerPresence.Change.Entered, presence.Update(atEdge: true));
        // Down from the edge, over the pixels of the window below, onto the island.
        Assert.Equal(PointerPresence.Change.LeaveStarted, presence.Update(atEdge: false));
        Assert.Equal(PointerPresence.Change.LeaveCancelled, presence.Update(overIsland: true));
        Assert.False(presence.LeaveGraceEnded());
        Assert.True(presence.Inside);
        // Away for good.
        Assert.Equal(PointerPresence.Change.LeaveStarted, presence.Update(overIsland: false));
        Assert.Equal(PointerPresence.Change.None, presence.Update(overIsland: false));
        Assert.True(presence.LeaveGraceEnded());
        Assert.False(presence.Inside);
        Assert.Equal(PointerPresence.Change.None, presence.Update(atEdge: false));
    }

    [Fact]
    public void TheCanvasHoldsEveryShape()
    {
        foreach (var size in Enum.GetValues<IslandSize>())
        {
            var layout = new IslandLayout(size);
            var canvas = layout.Canvas;
            foreach (var shape in new[]
                     {
                         layout.Shape(IslandState.Expanded),
                         layout.Shape(IslandState.Peek, new Wings(IslandLayout.MaximumWing), IslandLayout.MaximumMiddle),
                     })
            {
                var frame = layout.Frame(shape);
                Assert.True(frame.X >= 0 && frame.Right <= canvas.Width && frame.Bottom <= canvas.Height);
            }
        }
    }

    [Fact]
    public void TheWindowIsCentredAtTheTopOfItsMonitorInPhysicalPixels()
    {
        var canvas = (600.0, 260.0);
        Assert.Equal((660, 0, 600, 260), IslandLayout.Placement((0, 0, 1920, 1080), 1, canvas));
        // At 150 %, on a second monitor to the right.
        Assert.Equal((1920 + 830, 0, 900, 390), IslandLayout.Placement((1920, 0, 1920 + 2560, 1440), 1.5, canvas));
        // A monitor above the primary one has a negative top.
        Assert.Equal((-50, -1080, 600, 260), IslandLayout.Placement((-300, -1080, 800, 0), 1, canvas));
    }

    [Fact]
    public void TheIslandStepsAsideUnderFullScreenAppsUnlessSomethingNeedsTheUser()
    {
        Assert.True(IslandPresence.IsShown(fullScreenAppInFront: false, hasAlert: false));
        Assert.False(IslandPresence.IsShown(fullScreenAppInFront: true, hasAlert: false));
        Assert.True(IslandPresence.IsShown(fullScreenAppInFront: true, hasAlert: true));
    }
}

public class SpringTests
{
    private static double Peak(Spring spring)
    {
        var value = new SpringValue(0);
        value.Animate(1, spring, 0);
        var peak = 0.0;
        for (var t = 0.0; t < 2; t += 1.0 / 240) peak = Math.Max(peak, value.ValueAt(t));
        return peak;
    }

    [Fact]
    public void OpeningOvershootsALittleAndClosingNever()
    {
        var open = Peak(Spring.Open);
        Assert.InRange(open, 1.01, 1.15);
        Assert.True(Peak(Spring.Close) <= 1 + 1e-9);
        Assert.True(Peak(Spring.Reduced) <= 1 + 1e-9);
    }

    [Fact]
    public void ASpringStartsWhereItIsAndSettles()
    {
        var value = new SpringValue(124);
        value.Animate(480, Spring.Open, 10);
        Assert.Equal(124, value.ValueAt(10), 6);
        Assert.True(value.Step(10.1));
        var settle = Spring.Open.SettlingTime();
        Assert.InRange(settle, 0.4, 1.5);
        Assert.False(value.Step(10 + 3));
        Assert.Equal(480, value.ValueAt(13));
        Assert.False(value.IsMoving);
    }

    [Fact]
    public void TurningAroundMidWayKeepsTheValueAndItsSpeed()
    {
        var value = new SpringValue(0);
        value.Animate(100, Spring.Open, 0);
        var position = value.ValueAt(0.1);
        var speed = value.VelocityAt(0.1);
        Assert.True(speed > 0);
        value.Animate(0, Spring.Close, 0.1);
        Assert.Equal(position, value.ValueAt(0.1), 6);
        Assert.Equal(speed, value.VelocityAt(0.1), 4);
        // Still moving forward an instant later, before it turns back.
        Assert.True(value.ValueAt(0.11) > position);
    }

    [Fact]
    public void TheRestStateNeverAnimates()
    {
        var value = new SpringValue(32);
        value.Animate(32, Spring.Close, 5);
        Assert.False(value.IsMoving);
        Assert.False(value.Step(5));
    }

    [Fact]
    public void ReducedMotionUsesAShortSpringWithoutBounce()
    {
        Assert.Equal(Spring.Reduced, Spring.Toward(IslandState.Expanded, reduceMotion: true));
        Assert.Equal(Spring.Open, Spring.Toward(IslandState.Expanded, reduceMotion: false));
        Assert.Equal(Spring.Close, Spring.Toward(IslandState.Collapsed, reduceMotion: false));
    }
}

public class IslandMachineTests
{
    [Fact]
    public void AShortRestPeeksThenALongerOneOpens()
    {
        var machine = new IslandMachine();
        Assert.Equal([IslandEffect.StartRestTimer], machine.Handle(IslandEvent.PointerEntered));
        Assert.Equal(IslandState.Collapsed, machine.State);
        Assert.Equal([IslandEffect.StartHoverTimer], machine.Handle(IslandEvent.RestTimerFired));
        Assert.Equal(IslandState.Peek, machine.State);
        machine.Handle(IslandEvent.HoverTimerFired);
        Assert.Equal(IslandState.Expanded, machine.State);
    }

    [Fact]
    public void APointerPassingByDoesNothing()
    {
        var machine = new IslandMachine();
        machine.Handle(IslandEvent.PointerEntered);
        Assert.Equal([IslandEffect.CancelRestTimer], machine.Handle(IslandEvent.PointerExited));
        // A timer that fires late, once the pointer left, is ignored.
        machine.Handle(IslandEvent.RestTimerFired);
        Assert.Equal(IslandState.Collapsed, machine.State);
    }

    [Fact]
    public void AClickOpensAtOnceAndLeavingClosesAfterAGrace()
    {
        var machine = new IslandMachine();
        machine.Handle(IslandEvent.PointerEntered);
        machine.Handle(IslandEvent.Pressed);
        Assert.Equal(IslandState.Expanded, machine.State);
        Assert.Equal([IslandEffect.StartExitTimer], machine.Handle(IslandEvent.PointerExited));
        // Back in time: it stays.
        Assert.Equal([IslandEffect.CancelExitTimer], machine.Handle(IslandEvent.PointerEntered));
        machine.Handle(IslandEvent.PointerExited);
        machine.Handle(IslandEvent.ExitTimerFired);
        Assert.Equal(IslandState.Collapsed, machine.State);
    }

    [Fact]
    public void WithoutHoverOpeningOnlyAClickOpens()
    {
        var machine = new IslandMachine { OpensOnHover = false };
        machine.Handle(IslandEvent.PointerEntered);
        Assert.Empty(machine.Handle(IslandEvent.RestTimerFired));
        Assert.Equal(IslandState.Peek, machine.State);
        machine.Handle(IslandEvent.Pressed);
        Assert.Equal(IslandState.Expanded, machine.State);
    }

    [Fact]
    public void ARequestOpensTheIslandAndHoldsItUntilAnswered()
    {
        var machine = new IslandMachine();
        machine.Handle(IslandEvent.Requested);
        machine.Hold(true);
        Assert.Equal(IslandState.Expanded, machine.State);
        machine.Handle(IslandEvent.PointerEntered);
        Assert.Empty(machine.Handle(IslandEvent.PointerExited));
        machine.Handle(IslandEvent.ExitTimerFired);
        Assert.Equal(IslandState.Expanded, machine.State);
        // Answered while the pointer is away: it closes after the grace.
        Assert.Equal([IslandEffect.StartExitTimer], machine.Hold(false));
        machine.Handle(IslandEvent.ExitTimerFired);
        Assert.Equal(IslandState.Collapsed, machine.State);
    }
}

public class IntroScoreTests
{
    [Fact]
    public void TheScoreRunsInOrderAsOnTheMac()
    {
        Assert.True(IntroScore.TraceStart < IntroScore.TraceEnd);
        Assert.Equal(IntroScore.Swell, IntroScore.Bells[0]);
        Assert.Equal([0.42, 0.57, 0.72, 0.87], IntroScore.Bells);
        Assert.True(IntroScore.Tuck < IntroScore.End);
    }

    [Fact]
    public void BarsStayBetweenRestAndFullAndRingWithTheirBell()
    {
        for (var bar = 0; bar < 4; bar++)
        {
            for (var step = 0; step <= 300; step++)
            {
                var level = IntroScore.BarLevel(bar, step / 100.0);
                Assert.InRange(level, IntroScore.BarRest - 1e-9, 1 + 1e-9);
            }
            Assert.True(IntroScore.BarLevel(bar, IntroScore.Bells[bar] + 0.03) > IntroScore.BarLevel(bar, IntroScore.Bells[bar] - 0.01));
        }
        Assert.Equal(IntroScore.BarRest, IntroScore.BarLevel(0, 0));
    }

    [Fact]
    public void AWaveLeavesWithItsBellAndFades()
    {
        Assert.Null(IntroScore.WaveProgress(0, IntroScore.Bells[0] - 0.01));
        Assert.Equal(0, IntroScore.WaveProgress(0, IntroScore.Bells[0]));
        Assert.Null(IntroScore.WaveProgress(0, IntroScore.Bells[0] + IntroScore.WaveDuration + 0.01));
        Assert.True(IntroScore.Ease(0.5) > 0.5);
        Assert.Equal(0, IntroScore.WaveOpacity(0));
        Assert.Equal(1, IntroScore.WaveOpacity(0.1), 6);
        Assert.Equal(0, IntroScore.WaveOpacity(1), 6);
    }
}
