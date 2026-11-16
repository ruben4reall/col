/* Col's own glyphs, drawn with Cairo on a 24-unit grid: the island looks the same on every desktop, whatever icon theme
 * it has, and stays sharp at any scale. */

namespace Col.Glyphs {
    /* SF Symbol names scripts written for the Mac pass with --symbol, and the glyph that stands for each here. */
    public string resolve (string? symbol) {
        if (symbol == null || symbol == "") {
            return "hexagon";
        }
        var name = symbol.down ();
        string[,] table = {
            { "hammer", "hammer" }, { "wrench", "hammer" }, { "checkmark", "check" }, { "check", "check" },
            { "bell", "bell" }, { "cup", "cup" }, { "mug", "cup" }, { "coffee", "cup" }, { "timer", "timer" },
            { "clock", "timer" }, { "hourglass", "timer" }, { "alarm", "timer" }, { "arrow.down", "download" },
            { "tray", "download" }, { "download", "download" }, { "sparkle", "sparkle" }, { "star", "sparkle" },
            { "gear", "gear" }, { "music", "note" }, { "note", "note" }, { "bolt", "bolt" }, { "hand", "hand" },
            { "speaker", "speaker" }, { "play", "play" }, { "pause", "pause" }, { "terminal", "prompt" },
            { "chevron.left.forwardslash", "prompt" }, { "curlybraces", "prompt" }, { "pin", "pin" },
            { "exclamationmark", "alert" }, { "xmark", "close" }, { "battery", "battery" },
        };
        for (int i = 0; i < table.length[0]; i++) {
            if (name.has_prefix (table[i, 0]) || name.contains ("." + table[i, 0])) {
                return table[i, 1];
            }
        }
        if (is_known (name)) {
            return name;
        }
        return "hexagon";
    }

    public bool is_known (string name) {
        switch (name) {
        case "note": case "play": case "pause": case "next": case "previous": case "speaker": case "speaker-muted":
        case "bolt": case "timer": case "hand": case "check": case "check-circle": case "sparkle": case "prompt":
        case "gear": case "cup": case "hexagon": case "hammer": case "bell": case "download": case "grid": case "pin":
        case "pin-filled": case "close": case "plus": case "minus": case "alert": case "battery": case "copy":
            return true;
        default:
            return false;
        }
    }

    /* Draws a glyph in the square (x, y, size). */
    public void draw (Cairo.Context cr, string name, double x, double y, double size, Gdk.RGBA color) {
        cr.save ();
        cr.translate (x, y);
        cr.scale (size / 24.0, size / 24.0);
        cr.set_source_rgba (color.red, color.green, color.blue, color.alpha);
        cr.set_line_cap (Cairo.LineCap.ROUND);
        cr.set_line_join (Cairo.LineJoin.ROUND);
        switch (name) {
        case "play":
            cr.move_to (7.5, 4.5);
            cr.line_to (19.5, 12);
            cr.line_to (7.5, 19.5);
            cr.close_path ();
            cr.set_line_width (2.2);
            cr.fill_preserve ();
            cr.stroke ();
            break;
        case "pause":
            rounded (cr, 6, 4.5, 4.2, 15, 1.4);
            rounded (cr, 13.8, 4.5, 4.2, 15, 1.4);
            cr.fill ();
            break;
        case "next":
        case "previous":
            if (name == "previous") {
                cr.translate (24, 0);
                cr.scale (-1, 1);
            }
            cr.move_to (3, 6.5);
            cr.line_to (11.6, 12);
            cr.line_to (3, 17.5);
            cr.close_path ();
            cr.move_to (12, 6.5);
            cr.line_to (20.6, 12);
            cr.line_to (12, 17.5);
            cr.close_path ();
            cr.set_line_width (1.8);
            cr.fill_preserve ();
            cr.stroke ();
            break;
        case "note":
            cr.arc (8.2, 17.2, 3.4, 0, 2 * Math.PI);
            cr.fill ();
            rounded (cr, 10, 4.5, 2, 13, 0.6);
            cr.fill ();
            cr.move_to (10.5, 4.6);
            cr.line_to (18.5, 2.8);
            cr.line_to (18.5, 6.4);
            cr.line_to (11, 8.2);
            cr.close_path ();
            cr.fill ();
            break;
        case "speaker":
        case "speaker-muted":
            cr.move_to (3.5, 9);
            cr.line_to (7.5, 9);
            cr.line_to (12.5, 4.5);
            cr.line_to (12.5, 19.5);
            cr.line_to (7.5, 15);
            cr.line_to (3.5, 15);
            cr.close_path ();
            cr.set_line_width (1.4);
            cr.fill_preserve ();
            cr.stroke ();
            cr.set_line_width (2);
            if (name == "speaker-muted") {
                cr.move_to (16, 9);
                cr.line_to (21, 15);
                cr.move_to (21, 9);
                cr.line_to (16, 15);
                cr.stroke ();
            } else {
                cr.arc (12.5, 12, 4.2, -0.75, 0.75);
                cr.stroke ();
                cr.arc (12.5, 12, 7.8, -0.8, 0.8);
                cr.stroke ();
            }
            break;
        case "bolt":
            cr.move_to (14, 2);
            cr.line_to (4.8, 13.6);
            cr.line_to (11.2, 13.6);
            cr.line_to (9.8, 22);
            cr.line_to (19.2, 10.2);
            cr.line_to (12.8, 10.2);
            cr.close_path ();
            cr.fill ();
            break;
        case "timer":
            cr.set_line_width (2.2);
            cr.arc (12, 13.5, 8, 0, 2 * Math.PI);
            cr.stroke ();
            cr.move_to (12, 13.5);
            cr.line_to (12, 8.8);
            cr.stroke ();
            rounded (cr, 9.5, 1.8, 5, 2.4, 1);
            cr.fill ();
            break;
        case "hand":
            rounded (cr, 5.5, 4.6, 2.8, 11, 1.4);
            rounded (cr, 8.9, 2.6, 2.8, 12, 1.4);
            rounded (cr, 12.3, 3.2, 2.8, 11.5, 1.4);
            rounded (cr, 15.7, 5.4, 2.8, 10, 1.4);
            cr.fill ();
            rounded (cr, 5.5, 10.5, 13, 11.5, 5);
            cr.fill ();
            cr.save ();
            cr.translate (18.6, 14.6);
            cr.rotate (0.65);
            rounded (cr, -1.5, -5.5, 3, 7.5, 1.5);
            cr.restore ();
            cr.fill ();
            break;
        case "check":
            cr.set_line_width (2.8);
            cr.move_to (5, 12.6);
            cr.line_to (10, 17.4);
            cr.line_to (19.2, 7);
            cr.stroke ();
            break;
        case "check-circle":
            cr.arc (12, 12, 10, 0, 2 * Math.PI);
            cr.fill ();
            cr.set_source_rgba (0, 0, 0, 0.9);
            cr.set_line_width (2.6);
            cr.move_to (7.2, 12.4);
            cr.line_to (10.6, 15.8);
            cr.line_to (16.8, 8.6);
            cr.stroke ();
            break;
        case "alert":
            cr.arc (12, 12, 10, 0, 2 * Math.PI);
            cr.fill ();
            cr.set_source_rgba (0, 0, 0, 0.9);
            rounded (cr, 10.8, 6, 2.4, 8, 1.2);
            cr.fill ();
            cr.arc (12, 17.3, 1.4, 0, 2 * Math.PI);
            cr.fill ();
            break;
        case "sparkle":
            star (cr, 12, 12, 10.5, 2.2);
            cr.fill ();
            break;
        case "prompt":
            cr.set_line_width (2.4);
            cr.move_to (4.5, 6.5);
            cr.line_to (10.5, 12);
            cr.line_to (4.5, 17.5);
            cr.stroke ();
            cr.move_to (13, 18);
            cr.line_to (20, 18);
            cr.stroke ();
            break;
        case "gear":
            for (int i = 0; i < 8; i++) {
                cr.save ();
                cr.translate (12, 12);
                cr.rotate (i * Math.PI / 4);
                rounded (cr, -2, -10.6, 4, 5, 1);
                cr.restore ();
            }
            cr.fill ();
            cr.set_line_width (3.4);
            cr.arc (12, 12, 5.6, 0, 2 * Math.PI);
            cr.stroke ();
            break;
        case "cup":
            cr.set_line_width (2);
            cr.move_to (4.5, 8);
            cr.line_to (16.5, 8);
            cr.line_to (15.6, 16);
            cr.curve_to (15.4, 17.6, 14.2, 18.5, 12.8, 18.5);
            cr.line_to (8.2, 18.5);
            cr.curve_to (6.8, 18.5, 5.6, 17.6, 5.4, 16);
            cr.close_path ();
            cr.fill ();
            cr.arc (17.2, 11.6, 2.6, -Math.PI / 2, Math.PI / 2);
            cr.stroke ();
            cr.move_to (3, 21.2);
            cr.line_to (18, 21.2);
            cr.stroke ();
            cr.set_line_width (1.6);
            cr.move_to (8.5, 2.5);
            cr.curve_to (7.5, 3.8, 9.5, 4.6, 8.5, 6);
            cr.move_to (12.5, 2.5);
            cr.curve_to (11.5, 3.8, 13.5, 4.6, 12.5, 6);
            cr.stroke ();
            break;
        case "hammer":
            cr.save ();
            cr.translate (12, 12);
            cr.rotate (-Math.PI / 4);
            rounded (cr, -1.4, -3, 2.8, 14, 1.2);
            cr.fill ();
            rounded (cr, -6.5, -8.5, 12, 5.5, 1.6);
            cr.fill ();
            cr.restore ();
            break;
        case "bell":
            cr.move_to (12, 3);
            cr.curve_to (7.6, 3, 5.6, 6.4, 5.6, 10);
            cr.line_to (5.6, 14.6);
            cr.line_to (3.6, 17.6);
            cr.line_to (20.4, 17.6);
            cr.line_to (18.4, 14.6);
            cr.line_to (18.4, 10);
            cr.curve_to (18.4, 6.4, 16.4, 3, 12, 3);
            cr.close_path ();
            cr.fill ();
            cr.arc (12, 19.4, 2.4, 0, Math.PI);
            cr.fill ();
            break;
        case "download":
            cr.set_line_width (2.4);
            cr.move_to (12, 3);
            cr.line_to (12, 14.5);
            cr.move_to (7, 10);
            cr.line_to (12, 15);
            cr.line_to (17, 10);
            cr.stroke ();
            cr.move_to (4.5, 15);
            cr.line_to (4.5, 19.5);
            cr.line_to (19.5, 19.5);
            cr.line_to (19.5, 15);
            cr.stroke ();
            break;
        case "grid":
            rounded (cr, 3.5, 3.5, 7.4, 7.4, 2);
            rounded (cr, 13.1, 3.5, 7.4, 7.4, 2);
            rounded (cr, 3.5, 13.1, 7.4, 7.4, 2);
            rounded (cr, 13.1, 13.1, 7.4, 7.4, 2);
            cr.fill ();
            break;
        case "pin":
        case "pin-filled":
            cr.set_line_width (2);
            cr.move_to (12, 15);
            cr.line_to (12, 21.5);
            cr.stroke ();
            cr.move_to (8, 3);
            cr.line_to (16, 3);
            cr.line_to (15, 9);
            cr.line_to (18.5, 13);
            cr.line_to (18.5, 15);
            cr.line_to (5.5, 15);
            cr.line_to (5.5, 13);
            cr.line_to (9, 9);
            cr.close_path ();
            if (name == "pin-filled") {
                cr.fill_preserve ();
            }
            cr.stroke ();
            break;
        case "close":
            cr.set_line_width (2.4);
            cr.move_to (6.5, 6.5);
            cr.line_to (17.5, 17.5);
            cr.move_to (17.5, 6.5);
            cr.line_to (6.5, 17.5);
            cr.stroke ();
            break;
        case "plus":
        case "minus":
            cr.set_line_width (2.4);
            cr.move_to (5.5, 12);
            cr.line_to (18.5, 12);
            if (name == "plus") {
                cr.move_to (12, 5.5);
                cr.line_to (12, 18.5);
            }
            cr.stroke ();
            break;
        case "copy":
            cr.set_line_width (2);
            rounded (cr, 8, 8, 12, 12, 2.5);
            cr.stroke ();
            cr.move_to (4, 15);
            cr.line_to (4, 6.5);
            cr.curve_to (4, 5, 5, 4, 6.5, 4);
            cr.line_to (15, 4);
            cr.stroke ();
            break;
        default:
            // A hexagon: activities whose symbol Col does not draw.
            for (int i = 0; i < 6; i++) {
                double angle = Math.PI / 6 + i * Math.PI / 3;
                double px = 12 + 9.5 * Math.cos (angle), py = 12 + 9.5 * Math.sin (angle);
                if (i == 0) {
                    cr.move_to (px, py);
                } else {
                    cr.line_to (px, py);
                }
            }
            cr.close_path ();
            cr.set_line_width (2);
            cr.fill_preserve ();
            cr.stroke ();
            break;
        }
        cr.restore ();
    }

    /* A four-pointed star with concave sides. */
    public void star (Cairo.Context cr, double cx, double cy, double radius, double waist) {
        cr.move_to (cx, cy - radius);
        cr.curve_to (cx + waist * 0.3, cy - waist, cx + waist, cy - waist * 0.3, cx + radius, cy);
        cr.curve_to (cx + waist, cy + waist * 0.3, cx + waist * 0.3, cy + waist, cx, cy + radius);
        cr.curve_to (cx - waist * 0.3, cy + waist, cx - waist, cy + waist * 0.3, cx - radius, cy);
        cr.curve_to (cx - waist, cy - waist * 0.3, cx - waist * 0.3, cy - waist, cx, cy - radius);
        cr.close_path ();
    }

    public void rounded (Cairo.Context cr, double x, double y, double w, double h, double r) {
        r = double.min (r, double.min (w / 2, h / 2));
        cr.new_sub_path ();
        cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
        cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
        cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
        cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
        cr.close_path ();
    }

    public Gdk.RGBA rgba (Rgba color, double alpha = 1) {
        var result = Gdk.RGBA ();
        result.red = (float) color.red;
        result.green = (float) color.green;
        result.blue = (float) color.blue;
        result.alpha = (float) (color.alpha * alpha);
        return result;
    }

    public Gdk.RGBA white (double alpha = 1) {
        var result = Gdk.RGBA ();
        result.red = 1;
        result.green = 1;
        result.blue = 1;
        result.alpha = (float) alpha;
        return result;
    }

    /* The tile of a coding agent: a rounded square in its colour with its sign, drawn by Col rather than borrowed. */
    public void agent_tile (Cairo.Context cr, CodingAgent agent, double x, double y, double size, double alpha) {
        Rgba tint;
        switch (agent) {
        case CodingAgent.CLAUDE: tint = Rgba (0.85, 0.47, 0.34); break;
        case CodingAgent.CODEX: tint = Rgba (0.42, 0.45, 0.5); break;
        case CodingAgent.GEMINI: tint = Rgba (0.26, 0.52, 0.96); break;
        case CodingAgent.COPILOT: tint = Rgba (0.47, 0.36, 0.95); break;
        default: tint = Rgba (0.55, 0.55, 0.6); break;
        }
        var color = rgba (tint, alpha);
        cr.set_source_rgba (color.red, color.green, color.blue, color.alpha);
        rounded (cr, x, y, size, size, size * 0.26);
        cr.fill ();
        var mark = agent == CodingAgent.CLAUDE || agent == CodingAgent.GEMINI ? "sparkle" : "prompt";
        draw (cr, mark, x + size * 0.18, y + size * 0.18, size * 0.64, white (alpha));
    }

    /* A small widget showing one glyph, sized by CSS, coloured by the CSS `color`. */
    public class Icon : Gtk.Widget {
        string _name;
        public string glyph {
            get { return _name; }
            set {
                _name = value;
                queue_draw ();
            }
        }
        public int pixel_size = 16;
        /* A colour of its own, instead of the CSS one. */
        public Gdk.RGBA? tint = null;

        public Icon (string name, int pixel_size = 16) {
            _name = name;
            this.pixel_size = pixel_size;
            set_size_request (pixel_size, pixel_size);
            can_target = false;
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            int w = get_width (), h = get_height ();
            double size = double.min (w, h);
            var cr = snapshot.append_cairo (Graphene.Rect ().init (0, 0, w, h));
            draw (cr, _name, (w - size) / 2, (h - size) / 2, size, tint ?? get_color ());
        }
    }
}
