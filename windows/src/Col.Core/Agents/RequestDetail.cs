using System.Globalization;
using System.Text;

namespace Col.Core;

/// <summary>
/// The command, file or address of a permission request, the way the Allow card shows it: whole, never cut, with every
/// character that could hide part of it from the reader made visible. What Allow approves is what the card shows; a
/// command too long to check there is left to the terminal, which shows it whole.
/// </summary>
public sealed record RequestDetail
{
    /// <summary>The text to show: each line break marked ⏎, tabs ⇥, runs of spaces as ␣ (counted past three), control
    /// characters as their symbols, and invisible or blank ones by their code.</summary>
    public string Shown { get; }
    /// <summary>Whether the card shows it all at once. When it does not, Allow is off and the request is answered in
    /// the terminal.</summary>
    public bool FitsCard { get; }

    /// <summary>Characters on a line of the card's monospaced text in the smallest island: 12 px Cascadia Mono advances
    /// about 7.2 px, and the compact island's card has 376 px for it.</summary>
    public const int Columns = 52;
    /// <summary>Lines the card shows before it would have to scroll.</summary>
    public const int Lines = 3;

    public RequestDetail(string text)
    {
        Shown = Visible(text);
        FitsCard = LineCount(Shown, Columns) <= Lines;
    }

    internal static string Visible(string text)
    {
        var shown = new StringBuilder();
        var spaces = 0;
        void FlushSpaces()
        {
            switch (spaces)
            {
                case 0: break;
                case 1: shown.Append(' '); break;
                case 2 or 3: shown.Append('␣', spaces); break;
                default: shown.Append("␣×").Append(spaces.ToString(CultureInfo.InvariantCulture)); break;
            }
            spaces = 0;
        }
        // Scalar by scalar: a carriage return before a line break is a character of its own here, not part of it.
        foreach (var rune in text.EnumerateRunes())
        {
            if (rune.Value == ' ')
            {
                spaces++;
                continue;
            }
            FlushSpaces();
            shown.Append(rune.Value == '\n' ? "⏎\n" : Visible(rune));
        }
        FlushSpaces();
        var result = shown.ToString();
        // A command that ends with a line break shows the mark, not an empty line after it.
        return result.EndsWith("⏎\n", StringComparison.Ordinal) ? result[..^1] : result;
    }

    private static string Visible(Rune rune)
    {
        var value = rune.Value;
        switch (value)
        {
            case 0x09: return "⇥";
            // Other C0 controls and DEL as their Control Pictures: ␍, ␛ and the like.
            case <= 0x1F: return ((char)(0x2400 + value)).ToString();
            case 0x7F: return "␡";
        }
        var code = $"‹U+{value.ToString("X4", CultureInfo.InvariantCulture)}›";
        // Drawn as nothing, or as a blank: a combining grapheme joiner or a variation selector inside a word, a Hangul
        // filler or a blank Braille pattern standing for a space.
        if (IsDefaultIgnorable(value) || Blanks.Contains(value)) return code;
        return Rune.GetUnicodeCategory(rune) switch
        {
            UnicodeCategory.Control or UnicodeCategory.Format or UnicodeCategory.LineSeparator
                or UnicodeCategory.ParagraphSeparator or UnicodeCategory.SpaceSeparator or UnicodeCategory.PrivateUse
                or UnicodeCategory.OtherNotAssigned or UnicodeCategory.Surrogate => code,
            _ => rune.ToString(),
        };
    }

    /// <summary>Letters and symbols drawn blank: the Hangul fillers and the blank Braille pattern.</summary>
    private static readonly HashSet<int> Blanks = [0x115F, 0x1160, 0x3164, 0xFFA0, 0x2800];

    /// <summary>Unicode's Default_Ignorable_Code_Point property (DerivedCoreProperties.txt), which .NET does not
    /// expose: characters a font draws as nothing.</summary>
    private static readonly (int Low, int High)[] DefaultIgnorable =
    [
        (0x00AD, 0x00AD), (0x034F, 0x034F), (0x061C, 0x061C), (0x115F, 0x1160), (0x17B4, 0x17B5), (0x180B, 0x180F),
        (0x200B, 0x200F), (0x202A, 0x202E), (0x2060, 0x206F), (0x3164, 0x3164), (0xFE00, 0xFE0F), (0xFEFF, 0xFEFF),
        (0xFFA0, 0xFFA0), (0xFFF0, 0xFFF8), (0x1BCA0, 0x1BCA3), (0x1D173, 0x1D17A), (0xE0000, 0xE0FFF),
    ];

    private static bool IsDefaultIgnorable(int value) => DefaultIgnorable.Any(r => value >= r.Low && value <= r.High);

    /// <summary>Lines the text takes at <paramref name="columns"/> characters, broken at spaces as the card breaks it;
    /// a run with no space wider than a line takes as many as it needs. Wide characters count twice.</summary>
    internal static int LineCount(string text, int columns)
    {
        var total = 0;
        foreach (var line in text.Split('\n'))
        {
            var rows = 1;
            var used = 0;
            foreach (var word in line.Split(' '))
            {
                var width = 0;
                foreach (var rune in word.EnumerateRunes()) width += IsWide(rune.Value) ? 2 : 1;
                var needed = used == 0 ? width : used + 1 + width;
                if (needed <= columns)
                {
                    used = needed;
                    continue;
                }
                if (used > 0) rows++;
                while (width > columns)
                {
                    rows++;
                    width -= columns;
                }
                used = width;
            }
            total += rows;
        }
        return total;
    }

    /// <summary>East Asian wide characters and emoji, which take two columns of monospaced text.</summary>
    private static readonly (int Low, int High)[] WideRanges =
    [
        (0x1100, 0x115F), (0x2E80, 0xA4CF), (0xAC00, 0xD7A3), (0xF900, 0xFAFF), (0xFE30, 0xFE4F), (0xFF00, 0xFF60),
        (0xFFE0, 0xFFE6), (0x1F300, 0x1FAFF), (0x20000, 0x3FFFD),
    ];

    private static bool IsWide(int value) => WideRanges.Any(r => value >= r.Low && value <= r.High);
}
