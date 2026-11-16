using System.Net;
using System.Text;
using Col.Core;
using Microsoft.Extensions.Time.Testing;

namespace Col.Tests;

public class LyricsTests
{
    [Fact]
    public void ReadsTimedLinesInOrder()
    {
        var lyrics = Lyrics.Parse("[ar:Someone]\n[ti:A Song]\n[00:12.50]Second line\n[00:01.00]First line\n[00:20.00]\n")!;
        Assert.True(lyrics.IsSynced);
        // The first line is sung in about two seconds: the nine that follow are a pause.
        Assert.Equal(["First line", "", "Second line", ""], lyrics.Lines.Select(l => l.Text));
        Assert.Equal([1, 3, 12.5, 20], lyrics.Lines.Select(l => l.Time));
    }

    [Fact]
    public void WindowsLineEndingsAreRead()
    {
        var lyrics = Lyrics.Parse("[00:01.00]One\r\n[00:03.00]Two\r\n")!;
        Assert.Equal(["One", "Two"], lyrics.Lines.Where(l => !l.IsPause).Select(l => l.Text));
    }

    [Fact]
    public void OneLineCanCarrySeveralTimes()
    {
        var lyrics = Lyrics.Parse("[00:05.00][00:30.00]Chorus\n[00:10.00]Verse")!;
        Assert.Equal(["Chorus", "Verse", "Chorus"], lyrics.Lines.Where(l => !l.IsPause).Select(l => l.Text));
    }

    [Fact]
    public void AnOffsetShowsTheLinesSooner() => Assert.Equal(1.5, Lyrics.Parse("[offset:+500]\n[00:02.00]Hello")!.Lines[0].Time);

    [Fact]
    public void WordTimingIsKeptAndTheTextStaysClean()
    {
        var line = Lyrics.Parse("[00:12.00]<00:12.10> Hello <00:12.60> world")!.Lines.First(l => !l.IsPause);
        Assert.Equal("Hello world", line.Text);
        Assert.Equal([new LyricWord(12.1, "Hello"), new LyricWord(12.6, "world")], line.Words);
    }

    [Fact]
    public void LongGapsBecomePauses()
    {
        var lyrics = Lyrics.Parse("[00:10.00]Late start\n[00:12.00]Close\n[00:40.00]After a solo")!;
        Assert.Equal([true, false, false, true, false], lyrics.Lines.Select(l => l.IsPause));
        Assert.Equal(0, lyrics.Lines[0].Time);
    }

    [Fact]
    public void FindsTheLineBeingSung()
    {
        var lyrics = Lyrics.Parse("[00:01.00]a\n[00:03.00]b\n[00:05.00]c")!;
        Assert.Null(lyrics.IndexAt(0.5));
        Assert.Equal(0, lyrics.IndexAt(1));
        Assert.Equal(1, lyrics.IndexAt(4.9));
        Assert.Equal(2, lyrics.IndexAt(500));
        Assert.Equal(5, lyrics.NextChange(3));
        Assert.Null(lyrics.NextChange(5));
        Assert.Null(lyrics.IndexAt(double.NaN));
    }

    [Fact]
    public void ReadsEveryTimestampForm()
    {
        Assert.Equal(62, Lyrics.Timestamp("01:02"));
        Assert.Equal(62.5, Lyrics.Timestamp("01:02.5"));
        Assert.Equal(62.25, Lyrics.Timestamp("01:02.250"));
        Assert.Equal(62.25, Lyrics.Timestamp("01:02,250"));
        Assert.Equal(3662, Lyrics.Timestamp("1:01:02.00"));
        Assert.Null(Lyrics.Timestamp("ar:Someone"));
        Assert.Null(Lyrics.Timestamp("01:xx"));
    }

    [Fact]
    public void TimesNoTrackCouldReachAreNotRead()
    {
        foreach (var text in new[] { "00:inf", "00:infinity", "00:nan", "00:1e999", "99999999999999999999:00", "24:00:00", "-1:00" })
            Assert.Null(Lyrics.Timestamp(text));
        Assert.Equal(86_399, Lyrics.Timestamp("23:59:59"));
    }

    [Fact]
    public void ADamagedLineOrOffsetLeavesTheOthersFollowable()
    {
        var lyrics = Lyrics.Parse("[00:01.00] a\n[00:inf] b\n[00:1e999] c\n[00:03.00] <00:inf> d")!;
        Assert.Equal(["a", "d"], lyrics.Lines.Where(l => !l.IsPause).Select(l => l.Text));
        foreach (var offset in new[] { "-1e400", "1e400", "nan", "-99999999999" })
            Assert.Equal(1, Lyrics.Parse($"[offset:{offset}]\n[00:01.00] a")!.Lines[0].Time);
    }

    [Fact]
    public void TheWaitForTheNextLineIsAlwaysOneTheClockCanCount()
    {
        var lyrics = new Lyrics([new LyricLine(1, "a"), new LyricLine(3, "b"), new LyricLine(1e22, "c")], true);
        Assert.Equal(1.88, lyrics.Wait(1, 1)!.Value, 3);
        Assert.Equal(0.88, lyrics.Wait(1, 2)!.Value, 3);
        Assert.Equal(0.05, lyrics.Wait(2.99, 1));
        Assert.Equal(3600, lyrics.Wait(3, 1));
        Assert.Null(lyrics.Wait(1e22, 1));
        Assert.Null(lyrics.Wait(double.NaN, 1));
    }

    [Fact]
    public void PlainLyricsAreShownButNeverFollowed()
    {
        var lyrics = Lyrics.Plain("One\nTwo")!;
        Assert.False(lyrics.IsSynced);
        Assert.Null(lyrics.IndexAt(10));
        Assert.Null(Lyrics.Plain(" \n "));
        Assert.Null(Lyrics.Parse("no timing at all"));
    }

    [Fact]
    public void QueriesLeaveThePlayersNoiseOut()
    {
        var query = new LyricsQuery("Terrasser (Remastered 2020)", "Gradur feat. Heuss", "", 181);
        Assert.Equal("Terrasser", query.CleanTitle);
        Assert.Equal("Gradur", query.MainArtist);
        Assert.Equal(new LyricsQuery("terrasser", "GRADUR", "x", 181.2).CacheKey, query.CacheKey);
        Assert.True(query.Matches(182.5));
        Assert.False(query.Matches(190));
        Assert.True(query.Matches(null));
        Assert.Equal("Song", new LyricsQuery("Song - Live at Wembley", "A", "", 0).CleanTitle);
    }

    [Fact]
    public void TheDemoSongHasSyncedWords()
    {
        var lyrics = Lyrics.Parse(Demo.TrackLyrics)!;
        Assert.True(lyrics.IsSynced);
        Assert.Equal("We climb the pass at midnight", lyrics.Lines[lyrics.IndexAt(71)!.Value].Text);
    }
}

public sealed class LrclibClientTests : IDisposable
{
    private readonly string _cache = Path.Combine(Path.GetTempPath(), "col-lyrics-" + Guid.NewGuid().ToString("N"));
    private readonly FakeTimeProvider _time = new(DateTimeOffset.Parse("2026-11-16T10:00:00Z"));

    public void Dispose()
    {
        if (Directory.Exists(_cache)) Directory.Delete(_cache, recursive: true);
    }

    private sealed class FakeNetwork(Func<HttpRequestMessage, HttpResponseMessage> answer) : HttpMessageHandler
    {
        public List<HttpRequestMessage> Requests { get; } = [];

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Requests.Add(request);
            return Task.FromResult(answer(request));
        }
    }

    private static HttpResponseMessage Json(string json) =>
        new(HttpStatusCode.OK) { Content = new StringContent(json, Encoding.UTF8, "application/json") };

    private static readonly LyricsQuery Song = new("Midnight Pass (Remastered)", "The Harbour Lights feat. Someone", "Coastline", 214.4);

    [Fact]
    public async Task OnlyTheTitleArtistAlbumAndLengthAreSent()
    {
        var network = new FakeNetwork(_ => Json("""{"duration":214,"instrumental":false,"syncedLyrics":"[00:01.00]Hi","plainLyrics":"Hi"}"""));
        using var client = new LrclibClient(_cache, "3.0.0", network, _time);
        var answer = await client.LookUpAsync(Song);
        Assert.Equal(LyricsAnswerKind.Found, answer.Kind);
        Assert.True(answer.Lyrics!.IsSynced);
        var request = Assert.Single(network.Requests);
        Assert.Equal("https://lrclib.net/api/get?track_name=Midnight%20Pass&artist_name=The%20Harbour%20Lights&album_name=Coastline&duration=214",
            request.RequestUri!.AbsoluteUri);
        Assert.Equal("Col 3.0.0 for Windows (https://github.com/ruben4reall/col)", request.Headers.UserAgent.ToString());
    }

    [Fact]
    public async Task AnAnswerIsKeptAndATrackLookedUpOnce()
    {
        var network = new FakeNetwork(_ => Json("""{"duration":214,"syncedLyrics":"[00:01.00]Hi"}"""));
        using (var client = new LrclibClient(_cache, "3.0.0", network, _time)) await client.LookUpAsync(Song);
        using (var again = new LrclibClient(_cache, "3.0.0", network, _time))
        {
            var answer = await again.LookUpAsync(Song with { Title = "midnight pass" });
            Assert.Equal(LyricsAnswerKind.Found, answer.Kind);
        }
        Assert.Single(network.Requests);
        Assert.Single(Directory.GetFiles(_cache));
    }

    [Fact]
    public async Task AMissIsSearchedThenKeptForAWeek()
    {
        var network = new FakeNetwork(request => request.RequestUri!.AbsolutePath.EndsWith("/get", StringComparison.Ordinal)
            ? new HttpResponseMessage(HttpStatusCode.NotFound)
            : Json("""[{"duration":300,"syncedLyrics":"[00:01.00]Wrong length"},{"duration":215,"plainLyrics":"Plain only"},{"duration":214,"syncedLyrics":"[00:02.00]Right"}]"""));
        using var client = new LrclibClient(_cache, "3.0.0", network, _time);
        var answer = await client.LookUpAsync(Song);
        // The synced record of the right length wins.
        Assert.Equal("Right", answer.Lyrics!.Lines.First(l => !l.IsPause).Text);
        Assert.Equal(2, network.Requests.Count);
        Assert.Contains("/api/search?track_name=Midnight%20Pass&artist_name=The%20Harbour%20Lights", network.Requests[1].RequestUri!.AbsoluteUri);

        var empty = new FakeNetwork(_ => Json("[]"));
        using var other = new LrclibClient(_cache, "3.0.0", empty, _time);
        var unknown = new LyricsQuery("Unknown", "Nobody", "", 100);
        Assert.Equal(LyricsAnswerKind.NotFound, (await other.LookUpAsync(unknown)).Kind);
        Assert.Equal(LyricsAnswerKind.NotFound, (await other.LookUpAsync(unknown)).Kind);
        Assert.Equal(2, empty.Requests.Count);
        _time.Advance(TimeSpan.FromDays(8));
        await other.LookUpAsync(unknown);
        Assert.Equal(4, empty.Requests.Count);
    }

    [Fact]
    public async Task WhenLrclibAsksToSlowDownNothingIsAskedUntilItSays()
    {
        var network = new FakeNetwork(_ =>
        {
            var response = new HttpResponseMessage(HttpStatusCode.TooManyRequests);
            response.Headers.RetryAfter = new System.Net.Http.Headers.RetryConditionHeaderValue(TimeSpan.FromSeconds(120));
            return response;
        });
        using var client = new LrclibClient(_cache, "3.0.0", network, _time);
        Assert.Equal(LyricsAnswerKind.Unavailable, (await client.LookUpAsync(Song)).Kind);
        Assert.Equal(LyricsAnswerKind.Unavailable, (await client.LookUpAsync(Song with { Title = "Other" })).Kind);
        Assert.Single(network.Requests);
        // An unavailable answer is never kept: the track is asked again later.
        Assert.False(Directory.Exists(_cache) && Directory.GetFiles(_cache).Length > 0);
        _time.Advance(TimeSpan.FromSeconds(121));
        await client.LookUpAsync(Song);
        Assert.Equal(2, network.Requests.Count);
    }

    [Fact]
    public async Task InstrumentalsAreSaidSo()
    {
        var network = new FakeNetwork(_ => Json("""{"duration":214,"instrumental":true}"""));
        using var client = new LrclibClient(_cache, "3.0.0", network, _time);
        Assert.Equal(LyricsAnswerKind.Instrumental, (await client.LookUpAsync(Song)).Kind);
        client.ClearCache();
        Assert.Empty(Directory.GetFiles(_cache));
    }

    [Fact]
    public async Task AnUnreachableDatabaseIsTriedAgainLater()
    {
        var network = new FakeNetwork(_ => throw new HttpRequestException("offline"));
        using var client = new LrclibClient(_cache, "3.0.0", network, _time);
        Assert.Equal(LyricsAnswerKind.Unavailable, (await client.LookUpAsync(Song)).Kind);
        Assert.Equal(LyricsAnswerKind.Unavailable, (await client.LookUpAsync(Song)).Kind);
        Assert.Equal(2, network.Requests.Count);
    }
}
