using System.Globalization;
using System.Text.Json.Nodes;

namespace Col.Core;

/// <summary>
/// A live activity described by another program, through colctl, the local API or a <c>col://</c> link.
/// <code>{ "id": "build", "title": "Build", "subtitle": "12 of 40 files", "symbol": "hammer.fill",
///   "tint": "orange", "progress": 0.3, "text": "30%", "priority": "standard", "ttl": 60 }</code>
/// </summary>
public sealed record ActivityRequest(string Id)
{
    public string? Title { get; init; }
    public string? Subtitle { get; init; }
    /// <summary>An SF Symbol name, as on the Mac. Windows has no SF Symbols: Col draws the few it knows and a dot for
    /// the rest.</summary>
    public string? Symbol { get; init; }
    /// <summary>A colour name (white, green, orange, red, blue, purple, yellow, pink, teal, gray) or #RRGGBB.</summary>
    public string? Tint { get; init; }
    /// <summary>0 to 1: a ring on the right of the closed island.</summary>
    public double? Progress { get; init; }
    /// <summary>Short text on the right of the closed island, when there is no progress.</summary>
    public string? Text { get; init; }
    public string? Priority { get; init; }
    /// <summary>Seconds before the activity leaves by itself.</summary>
    public double? Ttl { get; init; }

    public sealed class InvalidException(string message) : Exception(message);

    /// <summary>Reads an activity from the JSON body of a request. Null when it is not an object with an id.</summary>
    public static ActivityRequest? FromJson(ReadOnlySpan<byte> body)
    {
        JsonNode? node;
        try { node = JsonNode.Parse(body); }
        catch (Exception) { return null; }
        if (node is not JsonObject json) return null;
        string? Text(string key) => json[key] is JsonValue value && value.TryGetValue(out string? text) ? text : null;
        double? Number(string key)
        {
            if (json[key] is not JsonValue value) return null;
            if (value.TryGetValue(out double number)) return number;
            if (value.TryGetValue(out string? text) &&
                double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed)) return parsed;
            return null;
        }
        var id = Text("id");
        if (id is null) return null;
        return new ActivityRequest(id)
        {
            Title = Text("title"), Subtitle = Text("subtitle"), Symbol = Text("symbol"), Tint = Text("tint"),
            Progress = Number("progress"), Text = Text("text"), Priority = Text("priority"), Ttl = Number("ttl"),
        };
    }

    /// <summary>Checks what a caller sent: an id of 64 characters at most, progress clamped to 0 to 1, a lifetime to
    /// one second to one day, and texts cut to what the island shows.</summary>
    public ActivityRequest Validated()
    {
        var trimmed = Id.Trim();
        if (trimmed.Length == 0) throw new InvalidException("missing id");
        if (trimmed.Length > 64) throw new InvalidException("id too long");
        return this with
        {
            Id = trimmed,
            Progress = Progress is { } p && double.IsFinite(p) ? Math.Clamp(p, 0, 1) : null,
            Ttl = Ttl is { } t && !double.IsNaN(t) ? Math.Clamp(t, 1, 24 * 3600) : null,
            Title = Cut(Title, 80),
            Subtitle = Cut(Subtitle, 120),
            Text = Cut(Text, 24),
        };
    }

    private static string? Cut(string? value, int length) => value is null || value.Length <= length ? value : value[..length];

    /// <summary>The board key: requests live in their own namespace, so they never replace Col's own activities.</summary>
    public string BoardId => "api." + Id;

    public Rgba ResolvedTint => Tint is null ? Rgba.White : ColorName.Parse(Tint) ?? Rgba.White;

    public ActivityPriority ResolvedPriority => Priority?.ToLowerInvariant() switch
    {
        "ambient" or "low" => ActivityPriority.Ambient,
        "alert" or "high" => ActivityPriority.Alert,
        _ => ActivityPriority.Standard,
    };

    public Activity ToActivity(DateTimeOffset now)
    {
        var tint = ResolvedTint;
        var leading = SymbolItem(Symbol, tint);
        CompactItem? trailing = Progress is { } progress
            ? CompactItem.Ring(progress, tint)
            : !string.IsNullOrEmpty(Text) ? CompactItem.Label(Text, tint) : null;
        return new Activity(BoardId, ResolvedPriority, new CompactPresentation(leading, trailing), now,
            Ttl is { } ttl ? now.AddSeconds(ttl) : null);
    }

    /// <summary>The glyph Col draws for an SF Symbol name, or a dot of the activity's colour.</summary>
    public static CompactItem SymbolItem(string? symbol, Rgba tint)
    {
        var name = symbol?.ToLowerInvariant() ?? "";
        string? glyph = name switch
        {
            _ when name.StartsWith("checkmark", StringComparison.Ordinal) => "check",
            _ when name.StartsWith("hand.raised", StringComparison.Ordinal) => "hand",
            _ when name.StartsWith("timer", StringComparison.Ordinal) || name.StartsWith("stopwatch", StringComparison.Ordinal)
                || name.StartsWith("hourglass", StringComparison.Ordinal) => "timer",
            _ when name.StartsWith("speaker", StringComparison.Ordinal) => "speaker",
            _ when name.StartsWith("music", StringComparison.Ordinal) => "music",
            _ when name.StartsWith("cup", StringComparison.Ordinal) || name.StartsWith("mug", StringComparison.Ordinal) => "cup",
            _ when name.StartsWith("bolt", StringComparison.Ordinal) => "bolt",
            _ when name.StartsWith("battery", StringComparison.Ordinal) => "battery",
            _ when name.StartsWith("hammer", StringComparison.Ordinal) || name.StartsWith("wrench", StringComparison.Ordinal) => "hammer",
            _ => null,
        };
        return glyph is null ? CompactItem.Dot(tint) : CompactItem.Symbol(glyph, tint);
    }
}

public static class ColorName
{
    public static Rgba? Parse(string value)
    {
        var name = value.Trim().ToLowerInvariant();
        switch (name)
        {
            case "white": return Rgba.White;
            case "green": return Rgba.Green;
            case "orange": return Rgba.Orange;
            case "red": return Rgba.Red;
            case "blue": return Rgba.Blue;
            case "purple": return Rgba.Purple;
            case "yellow": return Rgba.Yellow;
            case "pink": return new Rgba(1, 0.22, 0.47);
            case "teal": return new Rgba(0.19, 0.78, 0.82);
            case "gray" or "grey": return Rgba.Gray;
        }
        var hex = name.StartsWith('#') ? name[1..] : name;
        if (hex.Length == 3) hex = string.Concat(hex.Select(c => new string(c, 2)));
        if (hex.Length != 6 || !uint.TryParse(hex, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var number)) return null;
        return new Rgba(((number >> 16) & 0xFF) / 255.0, ((number >> 8) & 0xFF) / 255.0, (number & 0xFF) / 255.0);
    }
}

/// <summary>Activities other programs pushed, kept for the Live page. Safe to use from any thread.</summary>
public sealed class CustomActivities
{
    public sealed record Entry(ActivityRequest Request, DateTimeOffset? Expires, bool Finished, DateTimeOffset Updated)
    {
        public string Id => Request.Id;
    }

    private readonly object _lock = new();
    private readonly List<Entry> _entries = [];

    /// <summary>Raised after any change, on the thread that made it.</summary>
    public event Action? Changed;

    public IReadOnlyList<Entry> Entries
    {
        get { lock (_lock) return _entries.ToList(); }
    }

    public void Upsert(ActivityRequest request, DateTimeOffset now)
    {
        var entry = new Entry(request, request.Ttl is { } ttl ? now.AddSeconds(ttl) : null, false, now);
        lock (_lock)
        {
            var index = _entries.FindIndex(e => e.Id == request.Id);
            if (index >= 0) _entries[index] = entry;
            else _entries.Insert(0, entry);
        }
        Changed?.Invoke();
    }

    /// <summary>Marks an activity done; it lingers three seconds with a check mark, then leaves.</summary>
    public Entry? Finish(string id, string? text, DateTimeOffset now)
    {
        Entry? finished;
        lock (_lock)
        {
            var index = _entries.FindIndex(e => e.Id == id);
            if (index < 0) return null;
            var entry = _entries[index];
            var request = entry.Request with { Progress = null, Text = text ?? entry.Request.Text };
            finished = new Entry(request, now.AddSeconds(3), true, now);
            _entries[index] = finished;
        }
        Changed?.Invoke();
        return finished;
    }

    public bool Remove(string id)
    {
        int removed;
        lock (_lock) removed = _entries.RemoveAll(e => e.Id == id);
        if (removed > 0) Changed?.Invoke();
        return removed > 0;
    }

    public void Prune(DateTimeOffset now)
    {
        int removed;
        lock (_lock) removed = _entries.RemoveAll(e => e.Expires is { } end && end <= now);
        if (removed > 0) Changed?.Invoke();
    }

    /// <summary>The activity the island shows for an entry: a check mark once it is done.</summary>
    public static Activity ToActivity(Entry entry)
    {
        if (!entry.Finished) return entry.Request.ToActivity(entry.Updated) with { Expires = entry.Expires };
        var tint = entry.Request.ResolvedTint;
        return new Activity(entry.Request.BoardId, ActivityPriority.Transient,
            new CompactPresentation(ActivityRequest.SymbolItem(entry.Request.Symbol, tint), CompactItem.Symbol("check", Rgba.Green)),
            entry.Updated, entry.Expires);
    }
}
