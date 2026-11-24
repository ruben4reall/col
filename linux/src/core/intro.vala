/* The intro Col plays as it opens, as a score shared with the Mac (Packages/ColKit/Sources/ColCore/IntroScore.swift) and
 * Windows: light runs around the island, the island swells on the first bell of a rising chime, each bell sends a wave
 * out of it, then it settles back. The chime (data/sounds/intro.wav, scripts/make-intro-sound.swift) is written to these
 * very times. */

namespace Col.IntroScore {
    /* The light runs from the top of the island down to the middle of its lower edge. */
    public const double TRACE_START = 0.05;
    public const double TRACE_END = 0.42;
    /* The island swells with the first bell, and settles back as the chord lets go. */
    public const double SWELL = 0.42;
    public const double TUCK = 1.85;
    /* Everything has settled: the island is itself again. */
    public const double END = 2.45;
    /* A wave travels this long, fading as it goes, this far sideways on each side and up and down. */
    public const double WAVE_DURATION = 1.3;
    public const double WAVE_REACH_X = 150;
    public const double WAVE_REACH_Y = 48;
    /* Where the bars of the intro's equalizer rest, as a share of their full height. */
    public const double BAR_REST = 0.22;
    public const int BELLS = 4;

    /* The four bells, lowest first. Each one sends a wave. */
    public double bell (int index) {
        double[] times = { 0.42, 0.57, 0.72, 0.87 };
        return times[index.clamp (0, BELLS - 1)];
    }

    /* How strongly each bell's wave shows. */
    public double strength (int index) {
        double[] strengths = { 1, 0.8, 0.72, 0.95 };
        return strengths[index.clamp (0, BELLS - 1)];
    }

    public double smoothstep (double edge0, double edge1, double x) {
        double t = ((x - edge0) / (edge1 - edge0)).clamp (0, 1);
        return t * t * (3 - 2 * t);
    }

    /* How high bar `bar` (0 to 3, left to right) stands at `time`, from BAR_REST to 1: each bell lifts the bars nearest
     * its pitch, and they fall back as it fades. */
    public double bar_level (int bar, double time) {
        double lift = 0;
        for (int i = 0; i < BELLS; i++) {
            double since = time - bell (i);
            if (since < 0) {
                continue;
            }
            double attack = double.min (1, since / 0.03);
            double decay = i == BELLS - 1 ? 0.55 : 0.26;
            double nearness = Math.exp (-Math.pow (bar - i, 2) / 1.4);
            lift += attack * Math.exp (-since / decay) * nearness;
        }
        double chord = smoothstep (SWELL, SWELL + 0.5, time) * (1 - smoothstep (TUCK - 0.35, TUCK, time));
        lift += 0.16 * chord * (0.75 + 0.25 * Math.sin (time * 9 + bar * 1.7));
        return BAR_REST + (1 - BAR_REST) * double.min (1, lift);
    }

    /* How far a wave has travelled at `time`, 0 to 1, or a negative number before it leaves and after it has faded. */
    public double wave_progress (int index, double time) {
        double since = time - bell (index);
        if (since < 0 || since > WAVE_DURATION) {
            return -1;
        }
        return since / WAVE_DURATION;
    }

    /* A ripple's pace: leaving fast, slowing as it spreads. */
    public double ease (double progress) {
        return 1 - Math.pow (1 - progress.clamp (0, 1), 2.6);
    }

    /* How visible a wave is: it appears at once, then fades as it travels. */
    public double wave_opacity (double progress) {
        return progress < 0.1 ? progress / 0.1 : double.max (0, 1 - (progress - 0.1) / 0.9);
    }
}
