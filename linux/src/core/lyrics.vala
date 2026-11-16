/* Lyrics: LRC parsing, the line being sung, and what a lookup sends. The same rules as ColCore's Lyrics.swift. */

namespace Col {
    /* One line of lyrics and when it starts. An empty text marks a pause: an instrumental passage between two lines. */
    public class LyricLine {
        public double time;
        public string text;
        /* When the last timed word of the line starts, or -1 when the lyrics are not timed word by word. */
        public double last_word = -1;
        public int word_count = 0;

        public LyricLine (double time, string text) {
            this.time = time;
            this.text = text;
        }

        public bool is_pause () {
            return text.strip () == "";
        }
    }

    public class Lyrics {
        public GenericArray<LyricLine> lines = new GenericArray<LyricLine> ();
        /* False for plain lyrics, which have no timing: they are shown, never followed. */
        public bool is_synced;

        /* A pause longer than this between two lines shows as a pause of its own. */
        public const double PAUSE_THRESHOLD = 5;
        /* No track lasts a day: a time beyond is a damaged or hostile file, and is not read. */
        public const double LONGEST = 24 * 60 * 60;

        /* Reads LRC: `[mm:ss.xx] text` lines, several timestamps on one line, an `[offset:±ms]` tag, metadata tags
         * (ignored) and word timing in angle brackets. Null when no line is timed. */
        public static Lyrics? parse (string lrc) {
            double offset = 0;
            var lines = new GenericArray<LyricLine> ();
            foreach (unowned string raw_line in split_lines (lrc)) {
                string rest = raw_line.strip ();
                var times = new GenericArray<double?> ();
                while (rest.has_prefix ("[")) {
                    int close = rest.index_of_char (']');
                    if (close < 0) {
                        break;
                    }
                    string tag = rest.substring (1, close - 1);
                    double time;
                    if (timestamp (tag, out time)) {
                        times.add (time);
                    } else if (tag.down ().has_prefix ("offset:")) {
                        double value;
                        if (strict_double (tag.substring (7).strip (), out value) && Math.fabs (value) < LONGEST * 1000) {
                            // A positive offset shows the lyrics sooner, by milliseconds.
                            offset = value / 1000;
                        }
                    }
                    rest = rest.substring (close + 1);
                }
                if (times.length == 0) {
                    continue;
                }
                double last_word;
                int word_count;
                string text = word_timing (rest, out last_word, out word_count);
                foreach (var time in times) {
                    var line = new LyricLine ((!) time, text);
                    line.last_word = last_word;
                    line.word_count = word_count;
                    lines.add (line);
                }
            }
            if (lines.length == 0) {
                return null;
            }
            foreach (var line in lines) {
                line.time = double.max (0, line.time - offset);
                if (line.last_word >= 0) {
                    line.last_word = double.max (0, line.last_word - offset);
                }
            }
            // A stable sort: two lines at the same moment keep their order, and the first one is kept.
            lines.sort_with_data ((a, b) => a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
            var unique = new GenericArray<LyricLine> ();
            foreach (var line in lines) {
                if (unique.length > 0 && unique[unique.length - 1].time == line.time) {
                    continue;
                }
                unique.add (line);
            }
            var lyrics = new Lyrics ();
            lyrics.lines = with_pauses (unique);
            lyrics.is_synced = true;
            return lyrics;
        }

        /* Plain lyrics, one line per line, without timing. */
        public static Lyrics? plain (string text) {
            var lyrics = new Lyrics ();
            bool any = false;
            int index = 0;
            foreach (unowned string raw_line in split_lines (text)) {
                string line = raw_line.strip ();
                if (line != "") {
                    any = true;
                }
                lyrics.lines.add (new LyricLine (index++, line));
            }
            if (!any) {
                return null;
            }
            lyrics.is_synced = false;
            return lyrics;
        }

        /* Lines as Swift's `components(separatedBy: .newlines)` gives them. */
        static string[] split_lines (string text) {
            return Regex.split_simple ("\r\n|\r|\n", text);
        }

        /* The line being sung at a position of the track: the last one that has started. -1 before the first. */
        public int index_at (double position) {
            if (!is_synced || lines.length == 0 || position < lines[0].time) {
                return -1;
            }
            int low = 0, high = lines.length - 1;
            while (low < high) {
                int middle = (low + high + 1) / 2;
                if (lines[middle].time <= position) {
                    low = middle;
                } else {
                    high = middle - 1;
                }
            }
            return low;
        }

        /* The start of the next line after a position, or -1. */
        public double next_change (double position) {
            if (!is_synced) {
                return -1;
            }
            foreach (var line in lines) {
                if (line.time > position) {
                    return line.time;
                }
            }
            return -1;
        }

        /* How long to wait, from a position played at a rate, before the next line shows: a little early, so the line
         * arrives with the voice. An hour at most; -1 when no line follows or the wait cannot be told. */
        public double wait_after (double position, double rate) {
            if (position.is_nan () || rate.is_nan ()) {
                return -1;
            }
            double next = next_change (position);
            if (next < 0) {
                return -1;
            }
            double wait = (next - position) / double.max (rate, 0.1) - 0.12;
            if (wait.is_nan ()) {
                return -1;
            }
            return double.min (double.max (wait, 0.05), 60 * 60);
        }

        /* A number written in full, as Swift's Double(String) reads it: no spaces around, nothing after. */
        static bool strict_double (string text, out double value) {
            value = 0;
            if (text == "" || text != text.strip ()) {
                return false;
            }
            return double.try_parse (text, out value);
        }

        /* `mm:ss`, `mm:ss.xx` or `mm:ss.xxx`, and `hh:mm:ss.xx` for long tracks. */
        public static bool timestamp (string text, out double seconds) {
            seconds = 0;
            string[] parts = text.split (":");
            if (parts.length < 2 || parts.length > 3) {
                return false;
            }
            double total = 0;
            for (int i = 0; i < parts.length; i++) {
                string part = parts[i];
                if (part == "") {
                    return false;
                }
                bool last = i == parts.length - 1;
                double value;
                if (!strict_double (last ? part.replace (",", ".") : part, out value)) {
                    return false;
                }
                if (value.is_nan () || value.is_infinity () != 0 || value < 0) {
                    return false;
                }
                if (!last && value != Math.round (value)) {
                    return false;
                }
                // Only digits and a decimal point: no exponents, no hexadecimal.
                foreach (unowned uint8 c in part.data) {
                    if (!((c >= '0' && c <= '9') || c == '.' || c == ',')) {
                        return false;
                    }
                }
                total = total * 60 + value;
            }
            if (!(total < LONGEST)) {
                return false;
            }
            seconds = total;
            return true;
        }

        /* Takes word timing out of a line: `<00:12.10> Hello <00:12.60> world` reads "Hello world". */
        public static string word_timing (string text, out double last_word, out int word_count) {
            last_word = -1;
            word_count = 0;
            if (!text.contains ("<")) {
                return text.strip ();
            }
            var plain = new StringBuilder ();
            string rest = text;
            bool has_current = false;
            double current = 0;
            while (true) {
                int open = rest.index_of_char ('<');
                if (open < 0) {
                    break;
                }
                int close = rest.index_of_char ('>', open);
                if (close < 0) {
                    break;
                }
                string before = rest.substring (0, open);
                if (has_current && before.strip () != "") {
                    last_word = current;
                    word_count++;
                }
                plain.append (before);
                double time;
                has_current = timestamp (rest.substring (open + 1, close - open - 1), out time);
                current = time;
                rest = rest.substring (close + 1);
            }
            if (has_current && rest.strip () != "") {
                last_word = current;
                word_count++;
            }
            plain.append (rest);
            // Collapse every run of white space into one space.
            var words = new GenericArray<string> ();
            foreach (unowned string word in Regex.split_simple ("\\s+", plain.str.strip ())) {
                if (word != "") {
                    words.add (word);
                }
            }
            return string.joinv (" ", words.data);
        }

        /* A long gap after a line ends becomes a pause line of its own, so the view can show that the song goes on. */
        static GenericArray<LyricLine> with_pauses (GenericArray<LyricLine> lines) {
            var result = new GenericArray<LyricLine> ();
            if (lines.length > 0 && lines[0].time > PAUSE_THRESHOLD && !lines[0].is_pause ()) {
                result.add (new LyricLine (0, ""));
            }
            for (int i = 0; i < lines.length; i++) {
                var line = lines[i];
                result.add (line);
                if (line.is_pause () || i + 1 >= lines.length) {
                    continue;
                }
                var next = lines[i + 1];
                // A sung line lasts about as long as its words take, at most eight seconds.
                double sung = line.last_word >= 0
                    ? line.last_word + 1
                    : line.time + double.min (8, double.max (2, line.text.char_count () * 0.09));
                if (next.time - sung > PAUSE_THRESHOLD && !next.is_pause ()) {
                    result.add (new LyricLine (sung, ""));
                }
            }
            return result;
        }
    }

    /* What a lyrics lookup needs to know about a track, and how the answer is cached. */
    public class LyricsQuery {
        public string title;
        public string artist;
        public string album;
        public double duration;

        public LyricsQuery (string title, string artist, string album, double duration) {
            this.title = title;
            this.artist = artist;
            this.album = album;
            this.duration = duration;
        }

        /* Players add noise to titles that the lyrics never have: "(Remastered 2011)", "- Live", "[Explicit]". */
        public string clean_title () {
            string result = title;
            string[] patterns = {
                "\\s*[\\(\\[][^\\)\\]]*(remaster|live|explicit|version|edit|mono|stereo|deluxe|bonus)[^\\)\\]]*[\\)\\]]",
                "\\s+-\\s+.*(remaster|live|version|edit|mono|stereo).*$",
            };
            foreach (unowned string pattern in patterns) {
                try {
                    var regex = new Regex (pattern, RegexCompileFlags.CASELESS);
                    result = regex.replace (result, -1, 0, "");
                } catch (RegexError e) {
                }
            }
            return result.strip ();
        }

        /* The main artist, without featured ones: "Gradur feat. Heuss" reads "Gradur". */
        public string main_artist () {
            string[] separators = { " feat. ", " feat ", " ft. ", " ft ", " featuring ", ", ", " & ", " x ", " X " };
            string result = artist;
            foreach (unowned string separator in separators) {
                int index = result.down ().index_of (separator.down ());
                // " x " and " X " are the same separator once lowered; only a real match cuts.
                if (index >= 0) {
                    result = result.substring (0, index);
                }
            }
            return result.strip ();
        }

        /* A key for the cache, the same for the same track whatever player reports it. */
        public string cache_key () {
            return "%s\x1f%s\x1f%d".printf (main_artist ().down (), clean_title ().down (), (int) Math.round (duration));
        }

        /* True when a found track is this one: same length within two seconds when both lengths are known. */
        public bool matches (double found) {
            if (found < 0 || duration <= 0) {
                return true;
            }
            return Math.fabs (found - duration) <= 2;
        }
    }
}
