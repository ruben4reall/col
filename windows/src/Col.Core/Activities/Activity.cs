using System.Globalization;

namespace Col.Core;

/// <summary>A colour that crosses from the rules to the drawing without dragging a UI framework along.</summary>
public readonly record struct Rgba(double R, double G, double B, double A = 1)
{
    public static readonly Rgba White = new(1, 1, 1);
    /// <summary>#33D666: done, charging.</summary>
    public static readonly Rgba Green = new(0x33 / 255.0, 0xD6 / 255.0, 0x66 / 255.0);
    /// <summary>#FF9F0A: waiting, timers.</summary>
    public static readonly Rgba Orange = new(1, 0x9F / 255.0, 0x0A / 255.0);
    /// <summary>#FF453A: denied, low battery.</summary>
    public static readonly Rgba Red = new(1, 0x45 / 255.0, 0x3A / 255.0);
    /// <summary>#0A84FF: the accent of the island.</summary>
    public static readonly Rgba Blue = new(0x0A / 255.0, 0x84 / 255.0, 1);
    public static readonly Rgba Purple = new(0.69, 0.32, 0.87);
    public static readonly Rgba Yellow = new(1, 0.84, 0.04);
    public static readonly Rgba Gray = new(0.56, 0.56, 0.58);

    /// <summary>#RRGGBB.</summary>
    public string Hex => string.Create(CultureInfo.InvariantCulture,
        $"#{Channel(R):X2}{Channel(G):X2}{Channel(B):X2}");

    public byte RedByte => Channel(R);
    public byte GreenByte => Channel(G);
    public byte BlueByte => Channel(B);
    public byte AlphaByte => Channel(A);

    private static byte Channel(double value) => (byte)Math.Round(Math.Clamp(value, 0, 1) * 255);
}

/// <summary>What one side of the closed island shows.</summary>
public enum CompactKind
{
    /// <summary>A glyph of Col's own, by name: speaker, battery, timer, hand, check, cup, music, bolt.</summary>
    Glyph,
    /// <summary>The artwork of the track playing.</summary>
    Artwork,
    /// <summary>Bars that dance while the track plays.</summary>
    Equalizer,
    Text,
    /// <summary>A ring that fills from 0 to 1.</summary>
    Ring,
    /// <summary>A horizontal gauge from 0 to 1, for the volume.</summary>
    Level,
    Battery,
    /// <summary>A small arc that turns while something works.</summary>
    Spinner,
    /// <summary>The time left on a countdown, as text.</summary>
    Countdown,
    /// <summary>The logo of the coding agent behind a session.</summary>
    AgentLogo,
    /// <summary>A coloured dot, for activities whose symbol Col cannot draw.</summary>
    Dot,
}

/// <summary>One item of the closed island.</summary>
public sealed record CompactItem(CompactKind Kind)
{
    public string? Glyph { get; init; }
    public Rgba Tint { get; init; } = Rgba.White;
    public string? Text { get; init; }
    /// <summary>The level, progress or battery charge, from 0 to 1.</summary>
    public double Value { get; init; }
    public bool Active { get; init; }
    public DateTimeOffset? Ends { get; init; }
    public TimeSpan Total { get; init; }
    /// <summary>For an agent's logo: the agent's name.</summary>
    public string? Agent { get; init; }
    /// <summary>When the agent began to need the user: its logo hops a few times, then rests.</summary>
    public DateTimeOffset? Attention { get; init; }

    public static CompactItem Symbol(string glyph, Rgba? tint = null) => new(CompactKind.Glyph) { Glyph = glyph, Tint = tint ?? Rgba.White };
    public static CompactItem Label(string text, Rgba? tint = null) => new(CompactKind.Text) { Text = text, Tint = tint ?? Rgba.White };
    public static CompactItem Ring(double progress, Rgba tint) => new(CompactKind.Ring) { Value = Math.Clamp(progress, 0, 1), Tint = tint };
    public static CompactItem Level(double level, bool muted = false) => new(CompactKind.Level) { Value = Math.Clamp(level, 0, 1), Active = !muted };
    public static CompactItem Battery(double level, bool charging) => new(CompactKind.Battery) { Value = Math.Clamp(level, 0, 1), Active = charging };
    public static CompactItem Spinner(Rgba tint) => new(CompactKind.Spinner) { Tint = tint };
    public static CompactItem Equalizer(bool playing, Rgba? tint = null) => new(CompactKind.Equalizer) { Active = playing, Tint = tint ?? Rgba.White };
    public static CompactItem Artwork() => new(CompactKind.Artwork);
    public static CompactItem Countdown(DateTimeOffset? ends, TimeSpan total, string text, Rgba tint) =>
        new(CompactKind.Countdown) { Ends = ends, Total = total, Text = text, Tint = tint };
    public static CompactItem AgentLogo(string? agent, DateTimeOffset? attention = null) =>
        new(CompactKind.AgentLogo) { Agent = agent, Attention = attention };
    public static CompactItem Dot(Rgba tint) => new(CompactKind.Dot) { Tint = tint };
}

/// <summary>What the closed island shows: an item on each side, and optionally a line of text in the middle.</summary>
public sealed record CompactPresentation(CompactItem? Leading = null, CompactItem? Trailing = null, string? Middle = null);

/// <summary>Which activity wins the island when several want it.</summary>
public enum ActivityPriority
{
    /// <summary>Always-on context: the music playing.</summary>
    Ambient = 0,
    /// <summary>Something running: a timer, a build, an agent at work.</summary>
    Standard = 1,
    /// <summary>Something that needs the user: an agent waiting for approval, a low battery.</summary>
    Alert = 2,
    /// <summary>A brief acknowledgement: the volume, a charger plugged in.</summary>
    Transient = 3,
}

public sealed record Activity(
    string Id,
    ActivityPriority Priority,
    CompactPresentation Compact,
    DateTimeOffset Updated,
    DateTimeOffset? Expires = null);

/// <summary>Where an activity that is not urgent comes from, in the order the closed island prefers them.</summary>
public enum ActivitySource
{
    Agents,
    Timers,
    Scripts,
    Music,
    KeepAwake,
}

public static class ActivitySources
{
    /// <summary>The source of an activity, from its identifier; null for one that belongs to none (brief displays,
    /// alerts).</summary>
    public static ActivitySource? Of(string id) => id switch
    {
        "agents" => ActivitySource.Agents,
        "timer" => ActivitySource.Timers,
        "media" => ActivitySource.Music,
        "awake" => ActivitySource.KeepAwake,
        _ when id.StartsWith("api.", StringComparison.Ordinal) => ActivitySource.Scripts,
        _ => null,
    };
}

/// <summary>
/// Every live activity, and the rule that picks the one the closed island shows. Alerts and brief displays come first,
/// the highest priority then the most recent. Then the sources in order; within a source, the highest priority, then
/// the most recent.
/// </summary>
public sealed class ActivityBoard
{
    private readonly Dictionary<string, Activity> _activities = new(StringComparer.Ordinal);

    public IReadOnlyCollection<Activity> All => _activities.Values;

    public IReadOnlyList<ActivitySource> Ranking { get; set; } = Enum.GetValues<ActivitySource>();

    public void Upsert(Activity activity) => _activities[activity.Id] = activity;

    public bool Remove(string id) => _activities.Remove(id);

    public Activity? Get(string id) => _activities.GetValueOrDefault(id);

    /// <summary>Drops the activities whose time is up. Returns true when something left.</summary>
    public bool Prune(DateTimeOffset now)
    {
        var expired = _activities.Values.Where(a => a.Expires is { } end && end <= now).Select(a => a.Id).ToList();
        foreach (var id in expired) _activities.Remove(id);
        return expired.Count > 0;
    }

    public Activity? Current(DateTimeOffset now)
    {
        var live = _activities.Values.Where(a => a.Expires is not { } end || end > now).ToList();
        var urgent = live.Where(a => a.Priority >= ActivityPriority.Alert)
            .OrderByDescending(a => a.Priority).ThenByDescending(a => a.Updated).ThenBy(a => a.Id, StringComparer.Ordinal)
            .FirstOrDefault();
        if (urgent is not null) return urgent;
        int Rank(Activity activity)
        {
            var source = ActivitySources.Of(activity.Id);
            if (source is null) return Ranking.Count;
            var index = Ranking.ToList().IndexOf(source.Value);
            return index < 0 ? Ranking.Count : index;
        }
        return live.OrderBy(Rank).ThenByDescending(a => a.Priority).ThenByDescending(a => a.Updated)
            .ThenBy(a => a.Id, StringComparer.Ordinal).FirstOrDefault();
    }

    /// <summary>Whether something that needs the user is on the board.</summary>
    public bool HasAlert(DateTimeOffset now) =>
        _activities.Values.Any(a => a.Priority == ActivityPriority.Alert && (a.Expires is not { } end || end > now));

    /// <summary>The next moment an activity expires, to wake up exactly then instead of polling.</summary>
    public DateTimeOffset? NextExpiry(DateTimeOffset now) =>
        _activities.Values.Select(a => a.Expires).Where(e => e > now).Min();
}
