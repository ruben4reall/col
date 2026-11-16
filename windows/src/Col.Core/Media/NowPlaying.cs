using System.Globalization;

namespace Col.Core;

/// <summary>
/// What is playing, as Windows' media controls report it. Players report their position only now and then (on a seek,
/// a pause, a new track); the position now is worked out from the last report and the time since.
/// </summary>
public sealed record NowPlaying
{
    public bool IsPlaying { get; init; }
    public string Title { get; init; } = "";
    public string Artist { get; init; } = "";
    public string Album { get; init; } = "";
    /// <summary>Seconds; zero when the player does not say.</summary>
    public double Duration { get; init; }
    /// <summary>Position at <see cref="Reported"/>.</summary>
    public double Elapsed { get; init; }
    public DateTimeOffset Reported { get; init; }
    public double Rate { get; init; } = 1;
    /// <summary>The app that plays, as Windows names it: Spotify.exe, a browser's id.</summary>
    public string Source { get; init; } = "";

    public static readonly NowPlaying Nothing = new();

    /// <summary>Nothing has been reported, or the player went away.</summary>
    public bool IsEmpty => Title.Length == 0 && Artist.Length == 0;

    /// <summary>Identity of the track, to notice when a new one starts.</summary>
    public string TrackKey => $"{Title}\n{Artist}\n{Album}";

    /// <summary>Playback position at a moment, kept within the track.</summary>
    public double PositionAt(DateTimeOffset now)
    {
        var moving = IsPlaying ? Math.Max(Rate, 0) : 0;
        var position = Elapsed + (now - Reported).TotalSeconds * moving;
        return Duration > 0 ? Math.Clamp(position, 0, Duration) : Math.Max(position, 0);
    }

    /// <summary>Plays or pauses at once, keeping the position continuous, before the player confirms.</summary>
    public NowPlaying WithPlaying(bool playing, DateTimeOffset now) =>
        this with { Elapsed = PositionAt(now), Reported = now, IsPlaying = playing, Rate = playing ? Math.Max(Rate, 1) : Rate };

    public NowPlaying WithPosition(double position, DateTimeOffset now) =>
        this with { Elapsed = Duration > 0 ? Math.Clamp(position, 0, Duration) : Math.Max(position, 0), Reported = now };

    public LyricsQuery Query => new(Title, Artist, Album, Duration);

    /// <summary>"3:07", for the scrubber's labels.</summary>
    public static string Clock(double seconds)
    {
        var total = (int)Math.Max(0, Math.Floor(seconds));
        return total >= 3600
            ? string.Format(CultureInfo.InvariantCulture, "{0}:{1:00}:{2:00}", total / 3600, total / 60 % 60, total % 60)
            : string.Format(CultureInfo.InvariantCulture, "{0}:{1:00}", total / 60, total % 60);
    }
}
