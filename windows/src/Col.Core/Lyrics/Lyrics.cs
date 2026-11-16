using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Col.Core;

/// <summary>A word sung at a moment of its line, for lyrics timed word by word.</summary>
public readonly record struct LyricWord(double Time, string Text);

/// <summary>One line of lyrics, and when it starts. An empty text marks a pause: an instrumental passage.</summary>
public sealed record LyricLine(double Time, string Text, IReadOnlyList<LyricWord> Words)
{
    public LyricLine(double time, string text) : this(time, text, []) { }

    public bool IsPause => string.IsNullOrWhiteSpace(Text);

    public bool Equals(LyricLine? other) =>
        other is not null && Time.Equals(other.Time) && Text == other.Text && Words.SequenceEqual(other.Words);

    public override int GetHashCode() => HashCode.Combine(Time, Text, Words.Count);
}

/// <summary>The lyrics of a track: timed lines, or plain text when only that exists.</summary>
public sealed partial class Lyrics
{
    public IReadOnlyList<LyricLine> Lines { get; }
    /// <summary>False for plain lyrics, which have no timing: they are shown, never followed.</summary>
    public bool IsSynced { get; }

    public Lyrics(IReadOnlyList<LyricLine> lines, bool isSynced)
    {
        Lines = lines;
        IsSynced = isSynced;
    }

    /// <summary>A pause longer than this between two lines shows as a pause of its own (three dots).</summary>
    public const double PauseThreshold = 5;

    /// <summary>No track lasts a day: a time beyond is a damaged or hostile file, and is not read. Lyrics come from an
    /// open database anyone can write to.</summary>
    internal const double Longest = 24 * 60 * 60;

    /// <summary>
    /// Reads LRC: <c>[mm:ss.xx] text</c> lines, several timestamps on one line, an <c>[offset:±ms]</c> tag, metadata
    /// tags (ignored) and word timing in angle brackets. Null when no line is timed.
    /// </summary>
    public static Lyrics? Parse(string lrc)
    {
        double offset = 0;
        var lines = new List<LyricLine>();
        foreach (var raw in lrc.Split('\n'))
        {
            var rest = raw.Trim(' ', '\t', '\r');
            var times = new List<double>();
            while (rest.StartsWith('[') && rest.IndexOf(']') is var close and > 0)
            {
                var tag = rest[1..close];
                if (Timestamp(tag) is { } time)
                {
                    times.Add(time);
                }
                else if (tag.StartsWith("offset:", StringComparison.OrdinalIgnoreCase) &&
                         double.TryParse(tag["offset:".Length..].Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var value) &&
                         double.IsFinite(value) && Math.Abs(value) < Longest * 1000)
                {
                    // A positive offset shows the lyrics sooner, by milliseconds.
                    offset = value / 1000;
                }
                rest = rest[(close + 1)..];
            }
            if (times.Count == 0) continue;
            var (text, words) = WordTiming(rest);
            foreach (var time in times) lines.Add(new LyricLine(time, text, words));
        }
        if (lines.Count == 0) return null;
        var shifted = lines
            .Select(line => new LyricLine(Math.Max(0, line.Time - offset), line.Text,
                line.Words.Select(w => new LyricWord(Math.Max(0, w.Time - offset), w.Text)).ToList()))
            .OrderBy(line => line.Time) // Stable: lines at the same moment keep their order.
            .ToList();
        // Two lines at the same moment: keep the first.
        var unique = new List<LyricLine>();
        foreach (var line in shifted)
        {
            if (unique.Count == 0 || unique[^1].Time != line.Time) unique.Add(line);
        }
        return new Lyrics(WithPauses(unique), true);
    }

    /// <summary>Plain lyrics, one line per line, without timing.</summary>
    public static Lyrics? Plain(string text)
    {
        var lines = text.Split('\n').Select(l => l.Trim(' ', '\t', '\r')).ToList();
        if (!lines.Any(l => l.Length > 0)) return null;
        return new Lyrics(lines.Select((l, i) => new LyricLine(i, l)).ToList(), false);
    }

    /// <summary>The line being sung at a position of the track: the last one that has started. Null before the first.</summary>
    public int? IndexAt(double position)
    {
        if (!IsSynced || Lines.Count == 0 || !(position >= Lines[0].Time)) return null;
        int low = 0, high = Lines.Count - 1;
        while (low < high)
        {
            var middle = (low + high + 1) / 2;
            if (Lines[middle].Time <= position) low = middle;
            else high = middle - 1;
        }
        return low;
    }

    /// <summary>When the line on show next changes, after a position: the start of the next line.</summary>
    public double? NextChange(double position)
    {
        if (!IsSynced) return null;
        foreach (var line in Lines)
        {
            if (line.Time > position) return line.Time;
        }
        return null;
    }

    /// <summary>
    /// How long to wait, from a position played at a rate, before the next line shows: a little early, so the line
    /// arrives with the voice rather than after it. An hour at most; null when no line follows, or when the wait cannot
    /// be told.
    /// </summary>
    public double? Wait(double position, double rate)
    {
        if (NextChange(position) is not { } next) return null;
        var wait = (next - position) / Math.Max(rate, 0.1) - 0.12;
        if (double.IsNaN(wait)) return null;
        return Math.Min(Math.Max(wait, 0.05), 60 * 60);
    }

    /// <summary><c>mm:ss</c>, <c>mm:ss.xx</c> or <c>mm:ss.xxx</c>, and <c>hh:mm:ss.xx</c> for long tracks.</summary>
    internal static double? Timestamp(string text)
    {
        var parts = text.Split(':');
        if (parts.Length is < 2 or > 3 || parts.Any(p => p.Length == 0)) return null;
        double total = 0;
        for (var index = 0; index < parts.Length; index++)
        {
            var isLast = index == parts.Length - 1;
            var part = isLast ? parts[index].Replace(',', '.') : parts[index];
            // Digits and one decimal point only: "inf", "nan" and exponents are not times.
            if (!TimePart().IsMatch(part)) return null;
            if (!double.TryParse(part, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var value)) return null;
            if (!double.IsFinite(value) || value < 0 || (!isLast && value != Math.Round(value))) return null;
            total = total * 60 + value;
        }
        return total < Longest ? total : null;
    }

    [GeneratedRegex(@"^\d+(\.\d*)?$")]
    private static partial Regex TimePart();

    /// <summary>Takes word timing out of a line: <c>&lt;00:12.10&gt; Hello &lt;00:12.60&gt; world</c> reads "Hello world".</summary>
    internal static (string Text, IReadOnlyList<LyricWord> Words) WordTiming(string text)
    {
        if (!text.Contains('<')) return (text.Trim(' ', '\t'), []);
        var words = new List<LyricWord>();
        var plain = new StringBuilder();
        var rest = text;
        double? current = null;
        while (rest.IndexOf('<') is var open and >= 0 && rest.IndexOf('>', open) is var close and >= 0)
        {
            var before = rest[..open];
            if (current is { } time && before.Trim().Length > 0) words.Add(new LyricWord(time, before.Trim()));
            plain.Append(before);
            current = Timestamp(rest[(open + 1)..close]);
            rest = rest[(close + 1)..];
        }
        if (current is { } last && rest.Trim().Length > 0) words.Add(new LyricWord(last, rest.Trim()));
        plain.Append(rest);
        var collapsed = string.Join(' ', plain.ToString().Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        return (collapsed, words);
    }

    /// <summary>A long gap after a line ends becomes a pause line of its own, so the view can show the song goes on.</summary>
    internal static List<LyricLine> WithPauses(List<LyricLine> lines)
    {
        var result = new List<LyricLine>();
        // An introduction before the first words.
        if (lines.Count > 0 && lines[0].Time > PauseThreshold && !lines[0].IsPause) result.Add(new LyricLine(0, ""));
        for (var index = 0; index < lines.Count; index++)
        {
            var line = lines[index];
            result.Add(line);
            if (line.IsPause || index + 1 >= lines.Count) continue;
            var next = lines[index + 1];
            // A sung line lasts about as long as its words take, at most eight seconds.
            var sung = line.Words.Count > 0
                ? line.Words[^1].Time + 1
                : line.Time + Math.Min(8, Math.Max(2, line.Text.Length * 0.09));
            if (next.Time - sung > PauseThreshold && !next.IsPause) result.Add(new LyricLine(sung, ""));
        }
        return result;
    }
}

/// <summary>What a lyrics lookup needs to know about a track, and how the answer is cached.</summary>
public sealed partial record LyricsQuery(string Title, string Artist, string Album, double Duration)
{
    [GeneratedRegex(@"\s*[\(\[][^\)\]]*(remaster|live|explicit|version|edit|mono|stereo|deluxe|bonus)[^\)\]]*[\)\]]", RegexOptions.IgnoreCase)]
    private static partial Regex BracketNoise();

    [GeneratedRegex(@"\s+-\s+.*(remaster|live|version|edit|mono|stereo).*$", RegexOptions.IgnoreCase)]
    private static partial Regex DashNoise();

    /// <summary>Players add noise to titles that the lyrics never have: "(Remastered 2011)", "- Live", "[Explicit]".</summary>
    public string CleanTitle => DashNoise().Replace(BracketNoise().Replace(Title, ""), "").Trim();

    /// <summary>The main artist, without featured ones: "Gradur feat. Heuss" reads "Gradur".</summary>
    public string MainArtist
    {
        get
        {
            string[] separators = [" feat. ", " feat ", " ft. ", " ft ", " featuring ", ", ", " & ", " x ", " X "];
            var artist = Artist;
            foreach (var separator in separators)
            {
                var index = artist.IndexOf(separator, StringComparison.OrdinalIgnoreCase);
                if (index >= 0) artist = artist[..index];
            }
            return artist.Trim();
        }
    }

    /// <summary>A key for the cache, the same for the same track whatever player reports it.</summary>
    public string CacheKey =>
        $"{MainArtist.ToLowerInvariant()}\u001F{CleanTitle.ToLowerInvariant()}\u001F{(int)Math.Round(Duration, MidpointRounding.AwayFromZero)}";

    /// <summary>True when a found track is this one: same length within two seconds when both lengths are known.</summary>
    public bool Matches(double? found) => found is not { } length || Duration <= 0 || Math.Abs(length - Duration) <= 2;
}
