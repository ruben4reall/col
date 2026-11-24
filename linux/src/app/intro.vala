/* The intro Col plays as it opens (IntroScore, the Mac's score): light runs around the pill, the island swells with
 * Col's mark on the left and four bars that ring with the bells of a rising chime on the right, each bell sends a wave
 * out of it, then it settles back. IslandView plays it; what it draws around the island is here, and so is its chime.
 * Frames are asked for its two and a half seconds only; then nothing of it is left. */

namespace Col.Intro {
    const string RESOURCE = "/ch/rubencatalao/Col/";

    /* Draws an outline from Geometry into Cairo. */
    class Sink : Object, PathSink {
        unowned Cairo.Context cr;

        public Sink (Cairo.Context cr) {
            this.cr = cr;
        }

        public void move_to (double x, double y) {
            cr.move_to (x, y);
        }

        public void line_to (double x, double y) {
            cr.line_to (x, y);
        }

        public void curve_to (double x1, double y1, double x2, double y2, double x3, double y3) {
            cr.curve_to (x1, y1, x2, y2, x3, y3);
        }

        public void close_path () {
            cr.close_path ();
        }
    }

    Gdk.RGBA with_alpha (Gdk.RGBA color, double alpha) {
        var copy = color;
        copy.alpha = (float) alpha.clamp (0, 1);
        return copy;
    }

    Gdk.RGBA lighter (Gdk.RGBA color, double amount) {
        var copy = color;
        copy.red = (float) (color.red + (1 - color.red) * amount);
        copy.green = (float) (color.green + (1 - color.green) * amount);
        copy.blue = (float) (color.blue + (1 - color.blue) * amount);
        return copy;
    }

    /* A value that moves straight between keyframes at the given times of the score. */
    double keyframes (double time, double[] times, double[] values) {
        if (time <= times[0]) {
            return values[0];
        }
        for (int i = 1; i < times.length; i++) {
            if (time > times[i]) {
                continue;
            }
            double t = (time - times[i - 1]) / (times[i] - times[i - 1]);
            return values[i - 1] + (values[i] - values[i - 1]) * t;
        }
        return values[values.length - 1];
    }

    /* Behind the island: a soft light that swells with the bells, and a wave leaving with each bell. `pill` is the island
     * at rest, `swollen` the island as it swells, both centred on `cx`. */
    public void draw_back (Gtk.Snapshot snapshot, double time, Frame pill, Frame swollen, Gdk.RGBA accent, double width, double height) {
        var cr = snapshot.append_cairo (Graphene.Rect ().init (0, 0, (float) width, (float) height));
        double cy = pill.y + pill.height / 2;
        double glow = keyframes (time, { IntroScore.SWELL + 0.05, 0.57, 0.70, 0.82, 0.92, 1.45, IntroScore.TUCK + 0.1 },
                                 { 0, 0.85, 0.55, 0.8, 0.85, 0.5, 0 });
        if (glow > 0.01) {
            cr.save ();
            cr.translate (pill.cx, cy + 6);
            cr.scale (swollen.width * 0.75, pill.height * 1.9);
            var light = new Cairo.Pattern.radial (0, 0, 0, 0, 0, 1);
            light.add_color_stop_rgba (0, accent.red, accent.green, accent.blue, 0.55 * glow);
            light.add_color_stop_rgba (1, accent.red, accent.green, accent.blue, 0);
            cr.set_source (light);
            cr.arc (0, 0, 1, 0, 2 * Math.PI);
            cr.fill ();
            cr.restore ();
        }
        var color = lighter (accent, 0.25);
        for (int i = 0; i < IntroScore.BELLS; i++) {
            double progress = IntroScore.wave_progress (i, time);
            if (progress < 0) {
                continue;
            }
            double eased = IntroScore.ease (progress);
            var start = i == 0 ? pill : swollen;
            double w = start.width + (swollen.width - start.width + 2 * IntroScore.WAVE_REACH_X) * eased;
            double h = start.height + 2 * IntroScore.WAVE_REACH_Y * eased;
            double alpha = 0.85 * IntroScore.strength (i) * IntroScore.wave_opacity (progress);
            Geometry.outline (Frame (pill.cx, cy - h / 2, w, h, h / 2), new Sink (cr));
            cr.set_source_rgba (color.red, color.green, color.blue, alpha);
            cr.set_line_width (2.2 - 1.4 * eased);
            cr.stroke ();
        }
    }

    /* In front of the island: the line of light running down both sides of the pill to the middle of its lower edge,
     * and the spark where its two ends meet. */
    public void draw_front (Gtk.Snapshot snapshot, double time, Frame pill, Gdk.RGBA accent, double width, double height) {
        if (time > IntroScore.TRACE_END + 0.5) {
            return;
        }
        var cr = snapshot.append_cairo (Graphene.Rect ().init (0, 0, (float) width, (float) height));
        double drawn = ((time - IntroScore.TRACE_START) / (IntroScore.TRACE_END - IntroScore.TRACE_START)).clamp (0, 1);
        // Gathering speed toward the meeting point.
        drawn = drawn * drawn * (1.6 - 0.6 * drawn);
        double fade = time <= IntroScore.TRACE_END ? 1 : double.max (0, 1 - (time - IntroScore.TRACE_END) / 0.45);
        double radius = pill.height / 2;
        double straight = double.max (0, pill.width / 2 - radius);
        double length = straight * 2 + Math.PI * radius;
        double top = pill.y, bottom = pill.y + pill.height, cy = pill.y + radius;
        if (drawn > 0 && fade > 0) {
            cr.set_line_cap (Cairo.LineCap.ROUND);
            foreach (int side in new int[] { -1, 1 }) {
                double end = pill.cx + side * straight;
                double[] dashes = { length * drawn, length * 2 };
                for (int pass = 0; pass < 2; pass++) {
                    cr.new_path ();
                    cr.move_to (pill.cx, top);
                    cr.line_to (end, top);
                    if (side > 0) {
                        cr.arc (end, cy, radius, -Math.PI / 2, Math.PI / 2);
                    } else {
                        cr.arc_negative (end, cy, radius, -Math.PI / 2, -3 * Math.PI / 2);
                    }
                    cr.line_to (pill.cx, bottom);
                    cr.set_dash (dashes, 0);
                    if (pass == 0) {
                        // A halo in the accent under the white line.
                        cr.set_source_rgba (accent.red, accent.green, accent.blue, 0.45 * fade);
                        cr.set_line_width (5);
                    } else {
                        cr.set_source_rgba (1, 1, 1, 0.95 * fade);
                        cr.set_line_width (1.6);
                    }
                    cr.stroke ();
                }
            }
            cr.set_dash (null, 0);
        }
        double since = time - (IntroScore.TRACE_END - 0.02);
        if (since >= 0 && since <= 0.5) {
            double t = since / 0.5;
            double alpha = t < 0.18 ? t / 0.18 : 1 - (t - 0.18) / 0.82;
            double r = 9 * (0.3 + 2.1 * (1 - Math.pow (1 - t, 2)));
            var spark = new Cairo.Pattern.radial (pill.cx, bottom, 0, pill.cx, bottom, r);
            spark.add_color_stop_rgba (0, 1, 1, 1, alpha);
            spark.add_color_stop_rgba (0.4, accent.red, accent.green, accent.blue, 0.6 * alpha);
            spark.add_color_stop_rgba (1, accent.red, accent.green, accent.blue, 0);
            cr.set_source (spark);
            cr.arc (pill.cx, bottom, r, 0, 2 * Math.PI);
            cr.fill ();
        }
    }

    Gdk.Texture? mark_texture = null;

    /* Inside the swollen island: Col's mark in the left wing, four bars ringing with the bells in the right one. */
    public void draw_wings (Gtk.Snapshot snapshot, double time, Frame f, Gdk.RGBA accent, double alpha) {
        if (alpha <= 0.01) {
            return;
        }
        double side = 20;
        double cy = f.y + f.height / 2;
        if (mark_texture == null) {
            mark_texture = Gdk.Texture.from_resource (RESOURCE + "col-64.png");
        }
        if (mark_texture != null) {
            snapshot.push_opacity (alpha);
            var bounds = Graphene.Rect ().init ((float) (f.left () + 14), (float) (cy - side / 2), (float) side, (float) side);
            snapshot.append_scaled_texture ((!) mark_texture, Gsk.ScalingFilter.TRILINEAR, bounds);
            snapshot.pop ();
        }
        double gap = side * 0.12;
        double bar = (side - gap * 3) / 4;
        double x = f.right () - 14 - side;
        for (int i = 0; i < 4; i++) {
            double h = double.max (bar, side * IntroScore.bar_level (i, time));
            var rect = Graphene.Rect ().init ((float) (x + i * (bar + gap)), (float) (cy - h / 2), (float) bar, (float) h);
            var rounded = Gsk.RoundedRect ();
            rounded.init_from_rect (rect, (float) (bar / 2));
            snapshot.push_rounded_clip (rounded);
            snapshot.append_color (with_alpha (accent, alpha), rect);
            snapshot.pop ();
        }
    }

    /* The chime: through GTK's media player when it has a backend, otherwise through the sound server's own player
     * (PipeWire, PulseAudio, ALSA), whichever the system has. Silent when none can play it. */
    public class Chime : Object {
        Gtk.MediaStream? stream;

        public Chime () {
            var file = Gtk.MediaFile.for_resource (RESOURCE + "intro.wav");
            stream = file;
            if (file.get_error () != null) {
                play_elsewhere ();
                return;
            }
            file.notify["error"].connect (() => {
                if (file.get_error () != null) {
                    play_elsewhere ();
                }
            });
            file.volume = 0.6;
            file.play ();
        }

        void play_elsewhere () {
            stream = null;
            var path = Path.build_filename (Environment.get_user_cache_dir (), "col", "intro.wav");
            try {
                if (!FileUtils.test (path, FileTest.EXISTS)) {
                    var bytes = resources_lookup_data (RESOURCE + "intro.wav", ResourceLookupFlags.NONE);
                    DirUtils.create_with_parents (Path.get_dirname (path), 0700);
                    FileUtils.set_data (path, bytes.get_data ());
                }
            } catch (Error e) {
                return;
            }
            foreach (var player in new string[] { "pw-play", "paplay", "aplay" }) {
                if (Environment.find_program_in_path (player) == null) {
                    continue;
                }
                try {
                    string[] argv = player == "aplay" ? new string[] { player, "-q", path } : new string[] { player, path };
                    Pid pid;
                    Process.spawn_async (null, argv, null, SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL | SpawnFlags.STDERR_TO_DEV_NULL,
                                         null, out pid);
                    return;
                } catch (SpawnError e) {
                    continue;
                }
            }
        }
    }
}
