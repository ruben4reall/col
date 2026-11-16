/* Live activities other programs push through colctl, the socket or col:// links. The same JSON as on the Mac:
 *
 *     { "id": "build", "title": "Build", "subtitle": "12 of 40 files", "symbol": "hammer.fill",
 *       "tint": "orange", "progress": 0.3, "text": "30%", "priority": "standard", "ttl": 60 }
 */

namespace Col {
    /* Which activity wins the closed island when several want it: alert > standard > ambient, and Col's own brief
     * displays (volume, charger) above all for a moment. */
    public enum ActivityPriority {
        AMBIENT = 0,
        STANDARD = 1,
        ALERT = 2,
        TRANSIENT = 3;

        public static ActivityPriority parse (string? text) {
            switch (text != null ? text.down () : "") {
            case "ambient":
            case "low":
                return AMBIENT;
            case "alert":
            case "high":
                return ALERT;
            default:
                return STANDARD;
            }
        }

        public unowned string to_key () {
            switch (this) {
            case AMBIENT: return "ambient";
            case ALERT: return "alert";
            case TRANSIENT: return "transient";
            default: return "standard";
            }
        }
    }

    /* A colour as the rules see it, from 0 to 1. */
    public struct Rgba {
        public double red;
        public double green;
        public double blue;
        public double alpha;

        public Rgba (double red, double green, double blue, double alpha = 1) {
            this.red = red;
            this.green = green;
            this.blue = blue;
            this.alpha = alpha;
        }

        public static Rgba hex (uint value) {
            return Rgba (((value >> 16) & 0xff) / 255.0, ((value >> 8) & 0xff) / 255.0, (value & 0xff) / 255.0);
        }

        /* The colours of the island, from Col's brand: semantic green, orange and red follow macOS. */
        public static Rgba named_white () { return Rgba (1, 1, 1); }
        public static Rgba named_green () { return hex (0x33D666); }
        public static Rgba named_orange () { return hex (0xFF9F0A); }
        public static Rgba named_red () { return hex (0xFF453A); }
        public static Rgba named_blue () { return hex (0x0A84FF); }
        public static Rgba named_night () { return hex (0x05080A); }

        /* A colour name or a hex value such as #FF8800 or #F80. */
        public static bool parse (string? value, out Rgba color) {
            color = named_white ();
            if (value == null) {
                return false;
            }
            var name = value.strip ().down ();
            switch (name) {
            case "white": color = named_white (); return true;
            case "green": color = named_green (); return true;
            case "orange": color = named_orange (); return true;
            case "red": color = named_red (); return true;
            case "blue": color = named_blue (); return true;
            case "purple": color = Rgba (0.69, 0.32, 0.87); return true;
            case "yellow": color = Rgba (1, 0.84, 0.04); return true;
            case "pink": color = Rgba (1, 0.22, 0.47); return true;
            case "teal": color = Rgba (0.19, 0.78, 0.82); return true;
            case "gray":
            case "grey":
                color = Rgba (0.56, 0.56, 0.58);
                return true;
            default:
                break;
            }
            var hex_text = name.has_prefix ("#") ? name.substring (1) : name;
            if (hex_text.length == 3) {
                var doubled = new StringBuilder ();
                for (int i = 0; i < 3; i++) {
                    doubled.append_c (hex_text[i]);
                    doubled.append_c (hex_text[i]);
                }
                hex_text = doubled.str;
            }
            if (hex_text.length != 6) {
                return false;
            }
            uint64 number;
            try {
                if (!uint64.from_string (hex_text, out number, 16)) {
                    return false;
                }
            } catch (NumberParserError e) {
                return false;
            }
            color = hex ((uint) number);
            return true;
        }
    }

    public errordomain ActivityError {
        INVALID
    }

    /* A live activity described by another program. */
    public class ActivityRequest {
        public string id;
        public string? title;
        public string? subtitle;
        /* A symbol on the left of the island: one of Col's own glyphs, an SF Symbol name it knows, or an icon name. */
        public string? symbol;
        public string? tint;
        /* 0 to 1: a ring on the right. */
        public bool has_progress = false;
        public double progress = 0;
        /* Short text on the right, when there is no progress. */
        public string? text;
        public string? priority;
        /* Seconds before the activity leaves by itself. */
        public bool has_ttl = false;
        public double ttl = 0;

        public ActivityRequest (string id) {
            this.id = id;
        }

        public static ActivityRequest from_json (Json.Object object) throws ActivityError {
            var id = JsonText.get_string (object, "id");
            if (id == null) {
                throw new ActivityError.INVALID ("expected an activity with an id");
            }
            var request = new ActivityRequest (id);
            request.title = JsonText.get_string (object, "title");
            request.subtitle = JsonText.get_string (object, "subtitle");
            request.symbol = JsonText.get_string (object, "symbol");
            request.tint = JsonText.get_string (object, "tint");
            request.text = JsonText.get_string (object, "text");
            request.priority = JsonText.get_string (object, "priority");
            double value;
            if (JsonText.get_double (object, "progress", out value)) {
                request.has_progress = true;
                request.progress = value;
            }
            if (JsonText.get_double (object, "ttl", out value)) {
                request.has_ttl = true;
                request.ttl = value;
            }
            return request.validated ();
        }

        /* Checks what a caller sent: an id of 64 characters at most, progress kept between 0 and 1, ttl between a
         * second and a day, texts cut to what the island can show. */
        public ActivityRequest validated () throws ActivityError {
            var trimmed = id.strip ();
            if (trimmed == "" || trimmed.char_count () > 64) {
                throw new ActivityError.INVALID ("expected an activity with an id");
            }
            var copy = new ActivityRequest (trimmed);
            copy.title = cut (title, 80);
            copy.subtitle = cut (subtitle, 120);
            copy.symbol = cut (symbol, 80);
            copy.tint = tint;
            copy.text = cut (text, 24);
            copy.priority = priority;
            copy.has_progress = has_progress && !progress.is_nan ();
            copy.progress = copy.has_progress ? progress.clamp (0, 1) : 0;
            copy.has_ttl = has_ttl && !ttl.is_nan ();
            copy.ttl = copy.has_ttl ? ttl.clamp (1, 24 * 3600) : 0;
            return copy;
        }

        static string? cut (string? text, int characters) {
            if (text == null || text.char_count () <= characters) {
                return text;
            }
            return text.substring (0, text.index_of_nth_char (characters));
        }

        public Rgba resolved_tint () {
            Rgba color;
            if (Rgba.parse (tint, out color)) {
                return color;
            }
            return Rgba.named_white ();
        }

        public ActivityPriority resolved_priority () {
            return ActivityPriority.parse (priority);
        }
    }
}
