/* The closed island's content: an item on each side and, between them, a few words. Drawn straight into the island's
 * snapshot: nothing here takes clicks, the whole capsule opens the island. */

namespace Col {
    public class CompactRenderer {
        const double PAD = 7;
        const double GAP = 9;
        const double EMPTY_MIDDLE = 40;
        const double MIDDLE_MAX = 230;

        Gtk.Widget host;
        /* While an animated item is on show, the time drives it; frozen for screenshots. */
        public bool frozen = false;
        public Gdk.RGBA accent;

        public CompactRenderer (Gtk.Widget host) {
            this.host = host;
            accent = Glyphs.rgba (Rgba.named_blue ());
        }

        Pango.Layout layout (string text, double max_width) {
            var layout = host.create_pango_layout (text);
            var font = new Pango.FontDescription ();
            font.set_family (host.get_pango_context ().get_font_description ().get_family () ?? "Sans");
            font.set_weight (Pango.Weight.SEMIBOLD);
            font.set_absolute_size (13 * Pango.SCALE);
            layout.set_font_description (font);
            layout.set_single_paragraph_mode (true);
            layout.set_ellipsize (Pango.EllipsizeMode.END);
            if (max_width > 0) {
                layout.set_width ((int) (max_width * Pango.SCALE));
            }
            return layout;
        }

        double text_width (string text, double max_width = -1) {
            int w, h;
            layout (text, max_width).get_pixel_size (out w, out h);
            return w;
        }

        public double item_width (CompactItem? item) {
            if (item == null) {
                return 0;
            }
            switch (item.kind) {
            case ItemKind.LEVEL: return 64;
            case ItemKind.BATTERY: return 30;
            case ItemKind.TEXT: return double.min (text_width (item.text), 90);
            case ItemKind.EQUALIZER: return 20;
            case ItemKind.SPINNER: return 18;
            case ItemKind.ART: return 24;
            case ItemKind.AGENT: return 22;
            default: return 20;
            }
        }

        /* The width the closed island needs to show an activity. */
        public double width_for (Activity? activity) {
            if (activity == null) {
                return Geometry.REST_WIDTH;
            }
            double lead = item_width (activity.leading), trail = item_width (activity.trailing);
            double width = PAD * 2 + lead + trail;
            if (activity.middle != null && activity.middle != "") {
                double text = double.min (text_width ((!) activity.middle), MIDDLE_MAX);
                width += text + GAP * ((lead > 0 ? 1 : 0) + (trail > 0 ? 1 : 0));
            } else {
                width += lead > 0 && trail > 0 ? EMPTY_MIDDLE + 24 : 0;
            }
            width = double.max (width, lead > 0 && trail > 0 ? 150 : 108);
            return Math.ceil (double.min (width, Geometry.MAX_COMPACT_WIDTH));
        }

        public void draw (Gtk.Snapshot snapshot, Activity? activity, Frame f, double alpha) {
            if (activity == null || alpha <= 0.01) {
                return;
            }
            double cy = f.y + f.height / 2;
            double left = f.left () + PAD + (f.height - Geometry.PILL_HEIGHT) / 4;
            double right = f.right () - PAD - (f.height - Geometry.PILL_HEIGHT) / 4;
            double lead = item_width (activity.leading), trail = item_width (activity.trailing);
            if (activity.leading != null) {
                draw_item (snapshot, (!) activity.leading, left, cy, lead, alpha);
            }
            if (activity.trailing != null) {
                draw_item (snapshot, (!) activity.trailing, right - trail, cy, trail, alpha);
            }
            if (activity.middle != null && activity.middle != "") {
                double start = left + (lead > 0 ? lead + GAP : 0);
                double end = right - (trail > 0 ? trail + GAP : 0);
                double room = end - start;
                if (room > 12) {
                    var text = layout ((!) activity.middle, room);
                    int w, h;
                    text.get_pixel_size (out w, out h);
                    snapshot.save ();
                    snapshot.translate (Graphene.Point ().init ((float) (start + (room - w) / 2), (float) (cy - h / 2.0)));
                    snapshot.append_layout (text, Glyphs.rgba (activity.middle_tint, alpha));
                    snapshot.restore ();
                }
            }
        }

        void draw_item (Gtk.Snapshot snapshot, CompactItem item, double x, double cy, double width, double alpha) {
            switch (item.kind) {
            case ItemKind.ART:
                draw_art (snapshot, item.art, x, cy - 12, 24, alpha);
                return;
            case ItemKind.TEXT:
                var text = layout (item.text, 90);
                int w, h;
                text.get_pixel_size (out w, out h);
                snapshot.save ();
                snapshot.translate (Graphene.Point ().init ((float) (x + width - w), (float) (cy - h / 2.0)));
                snapshot.append_layout (text, Glyphs.rgba (item.tint, alpha));
                snapshot.restore ();
                return;
            default:
                break;
            }
            var cr = snapshot.append_cairo (Graphene.Rect ().init ((float) x - 2, (float) (cy - 14), (float) width + 4, 28));
            switch (item.kind) {
            case ItemKind.GLYPH:
                Glyphs.draw (cr, item.glyph, x, cy - 10, 20, Glyphs.rgba (item.tint, alpha));
                break;
            case ItemKind.AGENT:
                Glyphs.agent_tile (cr, item.agent, x, cy - 11, 22, alpha);
                if (item.flag) {
                    cr.set_source_rgba (1, 0.62, 0.04, alpha);
                    cr.arc (x + 20, cy - 9, 4.5, 0, 2 * Math.PI);
                    cr.fill ();
                }
                break;
            case ItemKind.RING:
                cr.set_line_width (2.6);
                cr.set_source_rgba (item.tint.red, item.tint.green, item.tint.blue, 0.25 * alpha);
                cr.arc (x + width / 2, cy, 8.2, 0, 2 * Math.PI);
                cr.stroke ();
                cr.set_source_rgba (item.tint.red, item.tint.green, item.tint.blue, alpha);
                cr.set_line_cap (Cairo.LineCap.ROUND);
                if (item.value > 0) {
                    cr.arc (x + width / 2, cy, 8.2, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * item.value);
                    cr.stroke ();
                }
                break;
            case ItemKind.LEVEL:
                Glyphs.rounded (cr, x, cy - 3, width, 6, 3);
                cr.set_source_rgba (1, 1, 1, 0.22 * alpha);
                cr.fill ();
                if (!item.flag && item.value > 0) {
                    Glyphs.rounded (cr, x, cy - 3, double.max (6, width * item.value), 6, 3);
                    cr.set_source_rgba (1, 1, 1, alpha);
                    cr.fill ();
                }
                break;
            case ItemKind.BATTERY:
                draw_battery (cr, x, cy, item.value, item.flag, alpha);
                break;
            case ItemKind.EQUALIZER:
                double[] heights = { 0.55, 0.95, 0.4, 0.75 };
                double t = frozen || !item.flag ? 0 : get_monotonic_time () / 1000000.0;
                for (int i = 0; i < 4; i++) {
                    double level = item.flag && !frozen
                        ? 0.3 + 0.7 * (0.5 + 0.5 * Math.sin (t * (5.2 + i * 1.7) + i * 1.3))
                        : (item.flag ? heights[i] : 0.25);
                    double h = 3 + 13 * level;
                    Glyphs.rounded (cr, x + 1 + i * 5, cy - h / 2, 3, h, 1.5);
                }
                cr.set_source_rgba (accent.red, accent.green, accent.blue, alpha);
                cr.fill ();
                break;
            case ItemKind.SPINNER:
                double turn = frozen ? 0.3 : (get_monotonic_time () / 1000000.0) % 1.0;
                cr.set_line_width (2.4);
                cr.set_line_cap (Cairo.LineCap.ROUND);
                cr.set_source_rgba (1, 1, 1, 0.2 * alpha);
                cr.arc (x + width / 2, cy, 7, 0, 2 * Math.PI);
                cr.stroke ();
                cr.set_source_rgba (accent.red, accent.green, accent.blue, alpha);
                double start = turn * 2 * Math.PI;
                cr.arc (x + width / 2, cy, 7, start, start + Math.PI * 0.9);
                cr.stroke ();
                break;
            default:
                break;
            }
        }

        public static void draw_battery (Cairo.Context cr, double x, double cy, double level, bool charging, double alpha) {
            cr.set_line_width (1.4);
            cr.set_source_rgba (1, 1, 1, 0.45 * alpha);
            Glyphs.rounded (cr, x + 0.7, cy - 6.3, 24, 12.6, 3.6);
            cr.stroke ();
            Glyphs.rounded (cr, x + 26, cy - 2.5, 2, 5, 1);
            cr.fill ();
            var fill = charging ? Rgba.named_green () : (level <= 0.2 ? Rgba.named_red () : Rgba.named_white ());
            cr.set_source_rgba (fill.red, fill.green, fill.blue, alpha);
            Glyphs.rounded (cr, x + 2.6, cy - 4.4, double.max (2.5, 20.2 * level), 8.8, 2.2);
            cr.fill ();
            if (charging) {
                Glyphs.draw (cr, "bolt", x + 7.5, cy - 5.5, 11, Glyphs.white (alpha));
            }
        }

        public static void draw_art (Gtk.Snapshot snapshot, Gdk.Texture? art, double x, double y, double size, double alpha) {
            var bounds = Graphene.Rect ().init ((float) x, (float) y, (float) size, (float) size);
            var clip = Gsk.RoundedRect ();
            clip.init_from_rect (bounds, (float) (size * 0.24));
            snapshot.push_rounded_clip (clip);
            if (alpha < 1) {
                snapshot.push_opacity (alpha);
            }
            if (art != null) {
                snapshot.append_texture ((!) art, bounds);
            } else {
                var color = Gdk.RGBA ();
                color.red = 0.18f;
                color.green = 0.2f;
                color.blue = 0.24f;
                color.alpha = 1;
                snapshot.append_color (color, bounds);
                var cr = snapshot.append_cairo (bounds);
                Glyphs.draw (cr, "note", x + size * 0.25, y + size * 0.25, size * 0.5, Glyphs.white (0.6));
            }
            if (alpha < 1) {
                snapshot.pop ();
            }
            snapshot.pop ();
        }
    }
}
