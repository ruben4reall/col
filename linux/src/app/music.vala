/* The music page: the player, and the song's lyrics beside it, the line being sung lit. Its clocks run only while the
 * island is open. */

namespace Col {
    class ArtView : Gtk.Widget {
        public Gdk.Texture? art;

        public ArtView (int size) {
            set_size_request (size, size);
            valign = Gtk.Align.CENTER;
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            CompactRenderer.draw_art (snapshot, art, 0, 0, double.min (get_width (), get_height ()), 1);
        }
    }

    class ScrubBar : Gtk.Widget {
        public double fraction = 0;
        public bool seekable = true;
        bool dragging = false;
        bool hovering = false;
        double drag_start = 0;

        public signal void seek (double fraction);

        construct {
            set_size_request (60, 16);
            hexpand = true;
            var motion = new Gtk.EventControllerMotion ();
            motion.enter.connect (() => {
                hovering = true;
                queue_draw ();
            });
            motion.leave.connect (() => {
                hovering = false;
                queue_draw ();
            });
            add_controller (motion);
            var drag = new Gtk.GestureDrag ();
            drag.drag_begin.connect ((x, y) => {
                if (!seekable) {
                    return;
                }
                dragging = true;
                drag_start = x;
                fraction = (x / get_width ()).clamp (0, 1);
                queue_draw ();
            });
            drag.drag_update.connect ((dx, dy) => {
                if (!dragging) {
                    return;
                }
                fraction = ((drag_start + dx) / get_width ()).clamp (0, 1);
                queue_draw ();
            });
            drag.drag_end.connect ((dx, dy) => {
                if (!dragging) {
                    return;
                }
                dragging = false;
                seek (fraction);
                queue_draw ();
            });
            add_controller (drag);
        }

        public bool is_dragging () {
            return dragging;
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            double w = get_width (), h = get_height ();
            bool big = (hovering || dragging) && seekable;
            double thickness = big ? 6 : 4;
            var cr = snapshot.append_cairo (Graphene.Rect ().init (0, 0, (float) w, (float) h));
            Glyphs.rounded (cr, 0, (h - thickness) / 2, w, thickness, thickness / 2);
            cr.set_source_rgba (1, 1, 1, 0.18);
            cr.fill ();
            double filled = double.max (thickness, w * fraction);
            Glyphs.rounded (cr, 0, (h - thickness) / 2, filled, thickness, thickness / 2);
            cr.set_source_rgba (1, 1, 1, big ? 1 : 0.82);
            cr.fill ();
        }
    }

    /* The lyrics, line by line: the line being sung bright, the others dim, the whole list gliding up as the song goes
     * on. A click on a line plays from there. */
    class LyricsView : Gtk.Widget {
        Model model;
        Lyrics? lyrics;
        int index = -1;
        Spring scroll = new Spring (0);
        uint tick_id = 0;
        int64 last_frame = 0;
        uint line_timer = 0;
        bool active = false;
        public bool frozen = false;
        GenericArray<Pango.Layout> layouts = new GenericArray<Pango.Layout> ();
        double[] tops = {};
        double[] heights = {};
        int laid_out_width = -1;
        const double SPACING = 8;
        const double ANCHOR = 0.24;

        public LyricsView (Model model) {
            this.model = model;
            hexpand = true;
            vexpand = true;
            overflow = Gtk.Overflow.HIDDEN;
            add_css_class ("col-lyrics");
            var click = new Gtk.GestureClick ();
            click.released.connect ((count, x, y) => seek_to_line (y));
            add_controller (click);
            var wheel = new Gtk.EventControllerScroll (Gtk.EventControllerScrollFlags.VERTICAL);
            wheel.scroll.connect ((dx, dy) => {
                if (lyrics != null && !lyrics.is_synced) {
                    double limit = tops.length > 0 ? tops[tops.length - 1] : 0;
                    scroll.jump_to ((scroll.value + dy * 24).clamp (0, limit));
                    queue_draw ();
                    return true;
                }
                return false;
            });
            add_controller (wheel);
        }

        public bool has_lyrics () {
            return lyrics != null && lyrics.lines.length > 0;
        }

        public void update () {
            var next = model.current_lyrics ();
            if (next != lyrics) {
                lyrics = next;
                index = -1;
                laid_out_width = -1;
                scroll.jump_to (0);
                queue_resize ();
            }
            sync ();
        }

        public void set_active (bool on) {
            active = on;
            sync ();
        }

        Pango.Layout make_layout (string text, int width) {
            var layout = create_pango_layout (text);
            var font = new Pango.FontDescription ();
            font.set_family (get_pango_context ().get_font_description ().get_family () ?? "Sans");
            font.set_weight (Pango.Weight.BOLD);
            font.set_absolute_size (14 * Pango.SCALE);
            layout.set_font_description (font);
            layout.set_wrap (Pango.WrapMode.WORD_CHAR);
            layout.set_width (width * Pango.SCALE);
            return layout;
        }

        void lay_out () {
            int width = get_width ();
            if (width <= 0 || width == laid_out_width) {
                return;
            }
            laid_out_width = width;
            layouts = new GenericArray<Pango.Layout> ();
            tops = {};
            heights = {};
            if (lyrics == null) {
                return;
            }
            double y = 0;
            foreach (var line in lyrics.lines) {
                var layout = make_layout (line.is_pause () ? "•  •  •" : line.text, width);
                int w, h;
                layout.get_pixel_size (out w, out h);
                layouts.add (layout);
                tops += y;
                heights += h;
                y += h + SPACING;
            }
            if (index >= 0 && index < tops.length) {
                scroll.jump_to (tops[index]);
            }
        }

        public override void size_allocate (int width, int height, int baseline) {
            lay_out ();
        }

        /* Finds the line now sung, glides to it, and wakes when the next one starts. */
        public void sync () {
            if (line_timer != 0) {
                Source.remove (line_timer);
                line_timer = 0;
            }
            var media = model.media;
            if (lyrics == null || !lyrics.is_synced || media == null) {
                return;
            }
            int64 now = get_monotonic_time ();
            double position = media.position_at (now);
            int next = lyrics.index_at (position);
            if (next != index) {
                index = next;
                lay_out ();
                double target = index >= 0 && index < tops.length ? tops[index] : 0;
                scroll.animate_to (target, Motion (0.55, 0.05));
                animate ();
            }
            if (active && media.playing && !frozen) {
                double wait = lyrics.wait_after (position, media.rate);
                if (wait > 0) {
                    line_timer = Timeout.add ((uint) (wait * 1000), () => {
                        line_timer = 0;
                        sync ();
                        return Source.REMOVE;
                    });
                }
            }
        }

        void animate () {
            if (!get_mapped () || frozen) {
                scroll.jump_to (scroll.target);
                queue_draw ();
                return;
            }
            if (tick_id != 0) {
                return;
            }
            last_frame = 0;
            tick_id = add_tick_callback ((widget, clock) => {
                int64 now = clock.get_frame_time ();
                double dt = last_frame == 0 ? 1.0 / 60 : (now - last_frame) / 1000000.0;
                last_frame = now;
                bool moving = scroll.step (dt);
                queue_draw ();
                if (!moving) {
                    tick_id = 0;
                    return Source.REMOVE;
                }
                return Source.CONTINUE;
            });
        }

        double anchor () {
            return lyrics != null && lyrics.is_synced ? get_height () * ANCHOR : 0;
        }

        void seek_to_line (double y) {
            if (lyrics == null || !lyrics.is_synced || model.media_control == null) {
                return;
            }
            double content = y + scroll.value - anchor ();
            for (int i = 0; i < tops.length; i++) {
                if (content >= tops[i] - SPACING / 2 && content <= tops[i] + heights[i] + SPACING / 2) {
                    var line = lyrics.lines[i];
                    model.media_control.seek (line.time + 0.05);
                    index = -1;
                    Timeout.add (60, () => {
                        sync ();
                        return Source.REMOVE;
                    });
                    return;
                }
            }
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            lay_out ();
            if (lyrics == null) {
                return;
            }
            double height = get_height ();
            double offset = anchor () - scroll.value;
            bool synced = lyrics.is_synced;
            for (int i = 0; i < layouts.length; i++) {
                double top = tops[i] + offset;
                if (top + heights[i] < -4 || top > height + 4) {
                    continue;
                }
                double alpha;
                if (!synced) {
                    alpha = 0.78;
                } else if (i == index) {
                    alpha = 1;
                } else {
                    alpha = i < index ? 0.26 : 0.36;
                }
                // Lines fade out toward the top and bottom edges.
                double fade = 22;
                double edge = double.min ((top + heights[i] / 2) / fade, (height - top - heights[i] / 2) / fade).clamp (0, 1);
                alpha *= synced && i == index ? double.max (edge, 0.6) : edge;
                if (alpha <= 0.01) {
                    continue;
                }
                snapshot.save ();
                snapshot.translate (Graphene.Point ().init (0, (float) top));
                snapshot.append_layout (layouts[i], Glyphs.white (alpha));
                snapshot.restore ();
            }
        }
    }

    public class MusicPage : Gtk.Box {
        Model model;
        Gtk.Stack stack;
        ArtView art;
        Gtk.Label title;
        Gtk.Label artist;
        Gtk.Label elapsed;
        Gtk.Label remaining;
        ScrubBar scrub;
        Gtk.Button play;
        Gtk.Button previous;
        Gtk.Button next;
        Gtk.Box player;
        LyricsView lyrics;
        Gtk.Label clock;
        Gtk.Label date;
        Gtk.Label nothing;
        bool active = false;
        uint clock_source = 0;
        public bool frozen = false;

        public MusicPage (Model model) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.model = model;
            stack = new Gtk.Stack ();
            stack.vexpand = true;
            append (stack);

            // The player.
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 20);
            row.add_css_class ("col-music");
            player = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            player.valign = Gtk.Align.CENTER;
            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            art = new ArtView (58);
            header.append (art);
            var names = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            names.valign = Gtk.Align.CENTER;
            names.hexpand = true;
            title = new Gtk.Label ("");
            title.add_css_class ("col-title");
            title.xalign = 0;
            title.ellipsize = Pango.EllipsizeMode.END;
            title.max_width_chars = 1;
            title.hexpand = true;
            artist = new Gtk.Label ("");
            artist.add_css_class ("col-subtitle");
            artist.xalign = 0;
            artist.ellipsize = Pango.EllipsizeMode.END;
            artist.max_width_chars = 1;
            names.append (title);
            names.append (artist);
            header.append (names);
            player.append (header);

            var times = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            elapsed = new Gtk.Label ("0:00");
            elapsed.add_css_class ("col-time");
            elapsed.width_chars = 4;
            elapsed.xalign = 0;
            remaining = new Gtk.Label ("-0:00");
            remaining.add_css_class ("col-time");
            remaining.width_chars = 5;
            remaining.xalign = 1;
            scrub = new ScrubBar ();
            scrub.seek.connect ((fraction) => {
                if (model.media != null && model.media_control != null && model.media.duration > 0) {
                    model.media_control.seek (fraction * model.media.duration);
                }
            });
            times.append (elapsed);
            times.append (scrub);
            times.append (remaining);
            player.append (times);

            var controls = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 22);
            controls.halign = Gtk.Align.CENTER;
            previous = glyph_button ("previous", _("Previous"), 24);
            play = glyph_button ("play", _("Play or pause"), 28);
            play.add_css_class ("col-play");
            next = glyph_button ("next", _("Next"), 24);
            previous.clicked.connect (() => {
                if (model.media_control != null) {
                    model.media_control.previous ();
                }
            });
            play.clicked.connect (() => {
                if (model.media_control != null) {
                    model.media_control.play_pause ();
                }
            });
            next.clicked.connect (() => {
                if (model.media_control != null) {
                    model.media_control.next ();
                }
            });
            controls.append (previous);
            controls.append (play);
            controls.append (next);
            player.append (controls);
            row.append (player);

            lyrics = new LyricsView (model);
            row.append (lyrics);
            stack.add_named (row, "player");

            // Nothing playing: the time.
            var idle = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            idle.valign = Gtk.Align.CENTER;
            idle.halign = Gtk.Align.CENTER;
            clock = new Gtk.Label ("");
            clock.add_css_class ("col-clock");
            date = new Gtk.Label ("");
            date.add_css_class ("col-subtitle");
            nothing = new Gtk.Label (_("Nothing playing"));
            nothing.add_css_class ("col-hint");
            nothing.margin_top = 8;
            idle.append (clock);
            idle.append (date);
            idle.append (nothing);
            stack.add_named (idle, "idle");

            model.media_changed.connect (update);
            model.lyrics_changed.connect (() => {
                lyrics.update ();
                update_layout ();
            });
            model.settings.changed.connect ((key) => {
                if (key == "lyrics") {
                    lyrics.update ();
                    update_layout ();
                }
            });
            update ();
        }

        public void freeze () {
            frozen = true;
            lyrics.frozen = true;
        }

        void update_layout () {
            bool words = lyrics.has_lyrics ();
            lyrics.visible = words;
            player.hexpand = !words;
            player.width_request = words ? 190 : -1;
            player.halign = words ? Gtk.Align.FILL : Gtk.Align.CENTER;
            if (!words) {
                player.width_request = 300;
            }
        }

        public void update () {
            var media = model.media;
            if (media == null || media.is_empty ()) {
                stack.visible_child_name = "idle";
                update_clock ();
                restart_timer ();
                return;
            }
            stack.visible_child_name = "player";
            art.art = media.art;
            art.queue_draw ();
            title.label = media.title != "" ? media.title : media.player;
            artist.label = media.artist;
            ((Glyphs.Icon) play.child).name = media.playing ? "pause" : "play";
            previous.sensitive = media.can_previous;
            next.sensitive = media.can_next;
            scrub.seekable = media.can_seek && media.duration > 0;
            update_position ();
            lyrics.update ();
            update_layout ();
            restart_timer ();
        }

        void update_position () {
            var media = model.media;
            if (media == null) {
                return;
            }
            double position = media.position_at (get_monotonic_time ());
            elapsed.label = TimerTool.format (Math.floor (position));
            remaining.label = media.duration > 0 ? "-" + TimerTool.format (Math.floor (double.max (0, media.duration - Math.floor (position)))) : "";
            if (!scrub.is_dragging ()) {
                scrub.fraction = media.duration > 0 ? position / media.duration : 0;
                scrub.queue_draw ();
            }
        }

        void update_clock () {
            var now = new DateTime.now_local ();
            clock.label = now.format ("%H:%M");
            // The day as the system's language writes it.
            date.label = now.format ("%A %e %B").replace ("  ", " ");
        }

        public void set_active (bool on) {
            active = on;
            lyrics.set_active (on);
            if (on) {
                update ();
            }
            restart_timer ();
        }

        /* Once a second while a song plays and the island is open; once a minute for the clock. */
        void restart_timer () {
            if (clock_source != 0) {
                Source.remove (clock_source);
                clock_source = 0;
            }
            if (!active || frozen) {
                return;
            }
            var media = model.media;
            if (media != null && !media.is_empty ()) {
                if (!media.playing) {
                    return;
                }
                clock_source = Timeout.add (1000, () => {
                    update_position ();
                    return Source.CONTINUE;
                });
            } else {
                var now = new DateTime.now_local ();
                uint wait = (uint) ((60 - now.get_seconds ()) * 1000) + 50;
                clock_source = Timeout.add (wait, () => {
                    clock_source = 0;
                    update_clock ();
                    restart_timer ();
                    return Source.REMOVE;
                });
            }
        }
    }
}
