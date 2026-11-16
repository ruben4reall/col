using Col.Core;

namespace Col.Tests;

public class ActivityBoardTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-11-16T10:00:00Z");

    private static Activity Make(string id, ActivityPriority priority, double secondsAgo = 0, double? expiresIn = null) =>
        new(id, priority, new CompactPresentation(), Now.AddSeconds(-secondsAgo), expiresIn is { } e ? Now.AddSeconds(e) : null);

    [Fact]
    public void AlertsComeFirstThenTheSourcesInOrder()
    {
        var board = new ActivityBoard();
        board.Upsert(Make("media", ActivityPriority.Ambient));
        board.Upsert(Make("timer", ActivityPriority.Standard, 10));
        Assert.Equal("timer", board.Current(Now)!.Id);
        board.Upsert(Make("agents", ActivityPriority.Standard, 20));
        // Agents come before timers, even when older.
        Assert.Equal("agents", board.Current(Now)!.Id);
        board.Upsert(Make("battery", ActivityPriority.Alert, 30));
        Assert.Equal("battery", board.Current(Now)!.Id);
        board.Upsert(Make("volume", ActivityPriority.Transient, 0, 1.5));
        Assert.Equal("volume", board.Current(Now)!.Id);
        // Once the volume has gone, the alert again.
        Assert.Equal("battery", board.Current(Now.AddSeconds(2))!.Id);
        Assert.True(board.HasAlert(Now));
    }

    [Fact]
    public void ExpiredActivitiesLeaveAndTheNextExpiryIsKnown()
    {
        var board = new ActivityBoard();
        board.Upsert(Make("api.a", ActivityPriority.Standard, 0, 5));
        board.Upsert(Make("api.b", ActivityPriority.Standard, 0, 9));
        Assert.Equal(Now.AddSeconds(5), board.NextExpiry(Now));
        Assert.False(board.Prune(Now.AddSeconds(1)));
        Assert.True(board.Prune(Now.AddSeconds(6)));
        Assert.Single(board.All);
        Assert.Null(new ActivityBoard().NextExpiry(Now));
    }

    [Fact]
    public void ARequestBecomesAnActivityInItsOwnNamespace()
    {
        var request = new ActivityRequest("build") { Symbol = "hammer.fill", Tint = "orange", Progress = 0.4, Ttl = 60 }.Validated();
        var activity = request.ToActivity(Now);
        Assert.Equal("api.build", activity.Id);
        Assert.Equal(ActivityPriority.Standard, activity.Priority);
        Assert.Equal(CompactKind.Ring, activity.Compact.Trailing!.Kind);
        Assert.Equal(Rgba.Orange, activity.Compact.Leading!.Tint);
        Assert.Equal("hammer", activity.Compact.Leading.Glyph);
        Assert.Equal(Now.AddSeconds(60), activity.Expires);
        // A symbol Windows has no drawing for becomes a dot of the activity's colour.
        Assert.Equal("cup", ActivityRequest.SymbolItem("cup.and.saucer.fill", Rgba.Blue).Glyph);
        Assert.Equal(CompactKind.Dot, ActivityRequest.SymbolItem("airplane", Rgba.Blue).Kind);
        Assert.Equal(ActivityPriority.Alert, (request with { Priority = "high" }).ResolvedPriority);
        Assert.Equal(ActivityPriority.Ambient, (request with { Priority = "ambient" }).ResolvedPriority);
    }

    [Fact]
    public void ColoursAreReadByNameOrHex()
    {
        Assert.Equal(Rgba.Green, ColorName.Parse("Green"));
        Assert.Equal("#FF8800", ColorName.Parse("#ff8800")!.Value.Hex);
        Assert.Equal("#FF8800", ColorName.Parse("f80")!.Value.Hex);
        Assert.Null(ColorName.Parse("#12"));
        Assert.Null(ColorName.Parse("chartreuse"));
        Assert.Equal("#33D666", Rgba.Green.Hex);
        Assert.Equal("#FF9F0A", Rgba.Orange.Hex);
        Assert.Equal("#FF453A", Rgba.Red.Hex);
        Assert.Equal("#0A84FF", Rgba.Blue.Hex);
    }

    [Fact]
    public void AFinishedActivityLingersWithACheckMark()
    {
        var custom = new CustomActivities();
        custom.Upsert(new ActivityRequest("build") { Progress = 0.5 }, Now);
        var finished = custom.Finish("build", "Done", Now)!;
        Assert.Null(finished.Request.Progress);
        Assert.Equal(Now.AddSeconds(3), finished.Expires);
        var activity = CustomActivities.ToActivity(finished);
        Assert.Equal(ActivityPriority.Transient, activity.Priority);
        Assert.Equal("check", activity.Compact.Trailing!.Glyph);
        custom.Prune(Now.AddSeconds(4));
        Assert.Empty(custom.Entries);
    }
}

public class ToolsTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-11-16T10:00:00Z");

    [Fact]
    public void TheClipboardKeepsTheNewestFirstWithoutRepeats()
    {
        var history = new ClipboardHistory(capacity: 3);
        history.Add("one", Now);
        history.Add("two", Now);
        history.Add("  ", Now);
        history.Add("one", Now);
        Assert.Equal(["one", "two"], history.Ordered.Select(e => e.Text));
        history.Add("three", Now);
        history.Add("four", Now);
        Assert.Equal(["four", "three", "one"], history.Ordered.Select(e => e.Text));
    }

    [Fact]
    public void PinsStayOnTopAndOutsideTheCapacity()
    {
        var history = new ClipboardHistory(capacity: 2);
        history.Add("keep", Now);
        history.TogglePin(history.Ordered[0].Id);
        history.Add("a", Now);
        history.Add("b", Now);
        history.Add("c", Now);
        Assert.Equal(["keep", "c", "b"], history.Ordered.Select(e => e.Text));
        history.Clear();
        Assert.Equal(["keep"], history.Ordered.Select(e => e.Text));
        // Copied again, a pin stays a pin.
        history.Add("keep", Now);
        Assert.True(history.Ordered[0].Pinned);
        Assert.Equal("a b…", ClipboardHistory.Preview("a\n\n  b   c", 3));
    }

    [Fact]
    public void ACountdownKnowsWhereItIsWithoutTicking()
    {
        var timer = new Countdown(TimeSpan.FromMinutes(5), Now);
        Assert.Equal(TimeSpan.FromMinutes(5), timer.Remaining(Now));
        Assert.Equal("4:55", Countdown.Format(timer.Remaining(Now.AddSeconds(5))));
        Assert.Equal("4:56", Countdown.Format(timer.Remaining(Now.AddSeconds(4.2))));
        var paused = timer.Paused(Now.AddSeconds(60));
        Assert.Equal(TimeSpan.FromMinutes(4), paused.Remaining(Now.AddHours(1)));
        var resumed = paused.Resumed(Now.AddHours(1));
        Assert.True(resumed.IsFinished(Now.AddHours(1).AddMinutes(4)));
        Assert.Equal("0:00", Countdown.Format(TimeSpan.Zero));
        Assert.Equal("1:02:03", Countdown.Format(TimeSpan.FromSeconds(3723)));
        Assert.Equal(0.5, timer.Fraction(Now.AddSeconds(150)), 6);
    }

    [Fact]
    public void ThePositionMovesOnlyWhilePlaying()
    {
        var track = Demo.Track(Now, 10);
        Assert.Equal(15, track.PositionAt(Now.AddSeconds(5)));
        var paused = track.WithPlaying(false, Now.AddSeconds(5));
        Assert.Equal(15, paused.PositionAt(Now.AddMinutes(5)));
        Assert.Equal(214, track.PositionAt(Now.AddHours(1)));
        Assert.Equal(100, track.WithPosition(100, Now).PositionAt(Now));
        Assert.Equal("3:34", NowPlaying.Clock(214));
        Assert.Equal("1:00:00", NowPlaying.Clock(3600));
        Assert.True(NowPlaying.Nothing.IsEmpty);
    }
}

public sealed class SettingsTests : IDisposable
{
    private readonly string _file = Path.Combine(Path.GetTempPath(), "col-settings-" + Guid.NewGuid().ToString("N"), "settings.json");

    public void Dispose()
    {
        var folder = Path.GetDirectoryName(_file)!;
        if (Directory.Exists(folder)) Directory.Delete(folder, recursive: true);
    }

    [Fact]
    public void TheDefaultsAreQuietAndLyricsAreOn()
    {
        var settings = ColSettings.Load(_file);
        Assert.False(settings.VisibleAtRest);
        Assert.True(settings.Lyrics);
        Assert.False(settings.LyricLineClosed);
        Assert.Equal(IslandSize.Standard, settings.Size);
        Assert.Equal("primary", settings.Monitor);
    }

    [Fact]
    public void SettingsAreSavedAndReadBack()
    {
        var settings = new ColSettings { VisibleAtRest = true, Size = IslandSize.Large, Lyrics = false, Monitor = @"\\.\DISPLAY2" };
        settings.Save(_file);
        Assert.Contains("\"size\": \"Large\"", File.ReadAllText(_file));
        var read = ColSettings.Load(_file);
        Assert.True(read.VisibleAtRest);
        Assert.Equal(IslandSize.Large, read.Size);
        Assert.False(read.Lyrics);
        Assert.Equal(@"\\.\DISPLAY2", read.Monitor);
    }

    [Fact]
    public void ADamagedFileGivesTheDefaults()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_file)!);
        File.WriteAllText(_file, "{ oops");
        Assert.True(ColSettings.Load(_file).Lyrics);
    }
}

public class DemoTests
{
    [Fact]
    public void EveryDemoStateHasAName()
    {
        Assert.Equal(DemoState.AgentPermission, Demo.Parse("agent-permission"));
        Assert.Equal(DemoState.Music, Demo.Parse("MUSIC"));
        Assert.Null(Demo.Parse("nope"));
        foreach (var name in new[] { "collapsed", "music", "lyrics", "agent-permission", "volume", "timer" })
            Assert.Contains(name, Demo.Names);
        var request = CodingAgent.Claude.EventFrom(Demo.PermissionRequest())!;
        Assert.Equal("Bash · git push origin main", request.RequestSummary);
        Assert.True(new RequestDetail(request.ToolDetail!).FitsCard);
    }
}
