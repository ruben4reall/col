using System.Globalization;

namespace Col.Core;

/// <summary>Recent text copies, newest first. Kept in memory only, pins included: nothing is written to disk.</summary>
public sealed class ClipboardHistory
{
    public sealed record Entry(Guid Id, string Text, DateTimeOffset Copied, bool Pinned);

    private readonly List<Entry> _entries = [];

    /// <summary>Unpinned entries kept; pinned ones never count against it.</summary>
    public int Capacity { get; }

    public ClipboardHistory(int capacity = 24) => Capacity = capacity;

    /// <summary>Pinned entries first, then the rest, newest first.</summary>
    public IReadOnlyList<Entry> Ordered => _entries.Where(e => e.Pinned).Concat(_entries.Where(e => !e.Pinned)).ToList();

    public const int LongestText = 20_000;

    /// <summary>Adds a copy. Blank text is ignored; copying something again moves it to the top instead of repeating it.</summary>
    public void Add(string text, DateTimeOffset when)
    {
        if (string.IsNullOrWhiteSpace(text)) return;
        var stored = text.Length > LongestText ? text[..LongestText] : text;
        var wasPinned = _entries.FirstOrDefault(e => e.Text == stored)?.Pinned ?? false;
        _entries.RemoveAll(e => e.Text == stored);
        _entries.Insert(0, new Entry(Guid.NewGuid(), stored, when, wasPinned));
        Trim();
    }

    public void TogglePin(Guid id)
    {
        var index = _entries.FindIndex(e => e.Id == id);
        if (index < 0) return;
        _entries[index] = _entries[index] with { Pinned = !_entries[index].Pinned };
        Trim();
    }

    public void Remove(Guid id) => _entries.RemoveAll(e => e.Id == id);

    /// <summary>Forgets everything but the pins.</summary>
    public void Clear() => _entries.RemoveAll(e => !e.Pinned);

    private void Trim()
    {
        var unpinned = 0;
        _entries.RemoveAll(e => !e.Pinned && ++unpinned > Capacity);
    }

    /// <summary>A copy in a line, for the list: blanks collapsed, cut at a length.</summary>
    public static string Preview(string text, int length = 80)
    {
        var line = string.Join(' ', text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        return line.Length <= length ? line : line[..length] + "…";
    }
}

/// <summary>A countdown that knows where it is at any moment without ticking.</summary>
public sealed record Countdown
{
    public TimeSpan Total { get; }
    public DateTimeOffset? Ends { get; private init; }
    /// <summary>Set while paused: what was left when it stopped.</summary>
    public TimeSpan? PausedRemaining { get; private init; }

    public Countdown(TimeSpan total, DateTimeOffset start)
    {
        Total = total < TimeSpan.FromSeconds(1) ? TimeSpan.FromSeconds(1) : total;
        Ends = start + Total;
    }

    public TimeSpan Remaining(DateTimeOffset now)
    {
        if (PausedRemaining is { } left) return left;
        if (Ends is not { } ends) return TimeSpan.Zero;
        var remaining = ends - now;
        return remaining < TimeSpan.Zero ? TimeSpan.Zero : remaining;
    }

    /// <summary>1 when it starts, 0 when it rings.</summary>
    public double Fraction(DateTimeOffset now) => Remaining(now).TotalSeconds / Total.TotalSeconds;

    public bool IsPaused => PausedRemaining is not null;

    public bool IsFinished(DateTimeOffset now) => !IsPaused && Remaining(now) <= TimeSpan.Zero;

    public Countdown Paused(DateTimeOffset now) => IsPaused ? this : this with { PausedRemaining = Remaining(now), Ends = null };

    public Countdown Resumed(DateTimeOffset now) =>
        PausedRemaining is { } left ? this with { Ends = now + left, PausedRemaining = null } : this;

    /// <summary>"4:05", or "1:02:03" past an hour; rounds up so it reads 0:00 only when it rings.</summary>
    public static string Format(TimeSpan remaining)
    {
        var total = (int)Math.Ceiling(Math.Max(0, remaining.TotalSeconds) - 1e-9);
        int hours = total / 3600, minutes = total / 60 % 60, seconds = total % 60;
        return hours > 0
            ? string.Format(CultureInfo.InvariantCulture, "{0}:{1:00}:{2:00}", hours, minutes, seconds)
            : string.Format(CultureInfo.InvariantCulture, "{0}:{1:00}", minutes, seconds);
    }
}
