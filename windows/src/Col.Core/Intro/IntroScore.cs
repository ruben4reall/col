namespace Col.Core;

/// <summary>
/// The intro Col plays as it opens, as a score shared with the Mac (Packages/ColKit/Sources/ColCore/IntroScore.swift)
/// and Linux: light runs around the island, the island swells on the first bell of a rising chime, each bell sends a
/// wave out of it, then it settles back. The chime (Assets\intro.wav, scripts/make-intro-sound.swift) is written to
/// these very times.
/// </summary>
public static class IntroScore
{
    /// <summary>The light runs from the top of the island down to the middle of its lower edge.</summary>
    public const double TraceStart = 0.05;
    public const double TraceEnd = 0.42;
    /// <summary>The four bells, lowest first. Each one sends a wave.</summary>
    public static readonly double[] Bells = [0.42, 0.57, 0.72, 0.87];
    /// <summary>How strongly each bell's wave shows.</summary>
    public static readonly double[] Strengths = [1, 0.8, 0.72, 0.95];
    /// <summary>The island swells with the first bell, and settles back as the chord lets go.</summary>
    public const double Swell = 0.42;
    public const double Tuck = 1.85;
    /// <summary>Everything has settled: the island is itself again.</summary>
    public const double End = 2.45;
    /// <summary>A wave travels this long, fading as it goes.</summary>
    public const double WaveDuration = 1.3;
    /// <summary>How far a wave travels from a floating island: sideways on each side, and up and down.</summary>
    public const double WaveReachX = 150;
    public const double WaveReachY = 48;
    /// <summary>Where the bars of the intro's equalizer rest, as a share of their full height.</summary>
    public const double BarRest = 0.22;

    /// <summary>
    /// How high bar <paramref name="bar"/> (0 to 3, left to right) stands at <paramref name="time"/>, from
    /// <see cref="BarRest"/> to 1: each bell lifts the bars nearest its pitch, and they fall back as it fades.
    /// </summary>
    public static double BarLevel(int bar, double time)
    {
        var lift = 0.0;
        for (var index = 0; index < Bells.Length; index++)
        {
            var since = time - Bells[index];
            if (since < 0) continue;
            var attack = Math.Min(1, since / 0.03);
            var decay = index == Bells.Length - 1 ? 0.55 : 0.26;
            var nearness = Math.Exp(-Math.Pow(bar - index, 2) / 1.4);
            lift += attack * Math.Exp(-since / decay) * nearness;
        }
        var chord = Smoothstep(Swell, Swell + 0.5, time) * (1 - Smoothstep(Tuck - 0.35, Tuck, time));
        lift += 0.16 * chord * (0.75 + 0.25 * Math.Sin(time * 9 + bar * 1.7));
        return BarRest + (1 - BarRest) * Math.Min(1, lift);
    }

    /// <summary>How far a wave has travelled at <paramref name="time"/>, 0 to 1, or null before it leaves and after it
    /// has faded.</summary>
    public static double? WaveProgress(int index, double time)
    {
        var since = time - Bells[index];
        if (since < 0 || since > WaveDuration) return null;
        return since / WaveDuration;
    }

    /// <summary>A ripple's pace: leaving fast, slowing as it spreads.</summary>
    public static double Ease(double progress) => 1 - Math.Pow(1 - Math.Clamp(progress, 0, 1), 2.6);

    /// <summary>How visible a wave is at <paramref name="progress"/>: it appears at once, then fades as it travels.</summary>
    public static double WaveOpacity(double progress) =>
        progress < 0.1 ? progress / 0.1 : Math.Max(0, 1 - (progress - 0.1) / 0.9);

    public static double Smoothstep(double edge0, double edge1, double x)
    {
        var t = Math.Clamp((x - edge0) / (edge1 - edge0), 0, 1);
        return t * t * (3 - 2 * t);
    }
}
