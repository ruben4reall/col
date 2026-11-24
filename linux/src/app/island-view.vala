/* The island itself: a black shape that springs between its states, the closed island's content inside it, and the
 * open island's pages, clipped to it. The rules that open and close it are the Mac's (IslandMachine): resting on it
 * makes it peek, then open after a short dwell; a click opens it at once; it closes shortly after the pointer leaves.
 *
 * Nothing ticks at rest: frames are asked of the frame clock only while a spring moves. */

namespace Col {
    /* Draws an outline from Geometry into Cairo. */
    class CairoSink : Object, PathSink {
        unowned Cairo.Context cr;

        public CairoSink (Cairo.Context cr) {
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

    public class IslandView : Gtk.Widget {
        public Model model;
        public ExpandedView expanded;
        CompactRenderer compact;

        public IslandState state { get; private set; default = IslandState.HIDDEN; }
        /* The largest state still on show while a spring brings the island to a smaller one. */
        IslandState visual = IslandState.HIDDEN;

        Spring width_spring;
        Spring height_spring;
        Spring top_spring;
        Spring radius_spring;
        Spring presence;
        Spring open_alpha;
        Spring compact_alpha;

        uint tick_id = 0;
        int64 last_frame = 0;
        bool pointer_inside = false;
        uint hover_source = 0;
        uint exit_source = 0;
        uint animation_source = 0;
        /* What the closed island shows. */
        Activity? shown;

        /* Distance between the top of the surface and the island. */
        public double gap = Geometry.GAP;
        /* Screenshots: no clock, no timers, nothing that moves. */
        public bool frozen = false;
        /* Kept open whatever the pointer does: a request waiting, a screenshot. */
        public bool held_open = false;
        /* Visible at rest, whatever the settings say (screenshots of the closed island). */
        public bool force_visible = false;

        /* The intro, while it plays (IntroScore): when it began, and how far it has come. */
        int64 intro_start = -1;
        bool intro_swelled = false;
        bool intro_tucked = false;
        uint intro_tick = 0;
        Intro.Chime? chime = null;
        /* The closed island's width while the intro swells it: a mark on the left, bars on the right. */
        const double INTRO_WIDTH = 176;

        public int envelope_width { get; private set; }
        public int envelope_height { get; private set; }

        /* The surface must change size, or the part of it that takes the pointer moved. */
        public signal void envelope_changed ();
        public signal void input_changed ();
        public signal void settings_requested ();

        public IslandView (Model model) {
            this.model = model;
            add_css_class ("col-island-view");
            compact = new CompactRenderer (this);
            expanded = new ExpandedView (model);
            expanded.set_parent (this);
            expanded.set_child_visible (false);

            var hidden = target_frame (IslandState.HIDDEN);
            width_spring = new Spring (hidden.width);
            height_spring = new Spring (hidden.height);
            top_spring = new Spring (hidden.y);
            radius_spring = new Spring (hidden.radius);
            presence = new Spring (0);
            open_alpha = new Spring (0);
            compact_alpha = new Spring (1);
            update_envelope ();

            var motion = new Gtk.EventControllerMotion ();
            motion.enter.connect ((x, y) => pointer_entered ());
            motion.leave.connect (() => pointer_left ());
            add_controller (motion);

            var click = new Gtk.GestureClick ();
            click.button = 0;
            click.released.connect ((count, x, y) => {
                if (click.get_current_button () == Gdk.BUTTON_SECONDARY) {
                    settings_requested ();
                } else if (state != IslandState.EXPANDED) {
                    open ();
                }
            });
            add_controller (click);

            model.changed.connect (on_model_changed);
            model.open_requested.connect ((page) => {
                expanded.show_page (page);
                open ();
            });
            model.settings.changed.connect ((key) => {
                if (key == "size") {
                    update_targets ();
                    queue_resize ();
                } else if (key == "visible-at-rest") {
                    if (state == IslandState.HIDDEN || state == IslandState.COLLAPSED) {
                        move_to (rest_state ());
                    }
                }
            });
            on_model_changed ();
        }

        ~IslandView () {
            expanded.unparent ();
        }

        bool reduce_motion () {
            var settings = Gtk.Settings.get_default ();
            return settings != null && !settings.gtk_enable_animations;
        }

        /* --------------------------------------------------------------------------------------------------------- */
        /* State */

        public IslandState rest_state () {
            if (intro_holds () || model.current () != null || model.settings.visible_at_rest || force_visible) {
                return IslandState.COLLAPSED;
            }
            return IslandState.HIDDEN;
        }

        bool is_held () {
            return held_open || model.agents.pending.length > 0;
        }

        public void move_to (IslandState next) {
            if (next == state) {
                update_targets ();
                return;
            }
            state = next;
            if (level (next) > level (visual)) {
                visual = next;
            }
            if (next == IslandState.EXPANDED) {
                expanded.set_child_visible (true);
                expanded.opened ();
                queue_allocate ();
            } else {
                expanded.closed ();
            }
            update_targets ();
            update_animation_timer ();
        }

        public void open () {
            cut_intro ();
            cancel (ref hover_source);
            cancel (ref exit_source);
            move_to (IslandState.EXPANDED);
        }

        public void close () {
            cancel (ref hover_source);
            cancel (ref exit_source);
            move_to (pointer_inside ? IslandState.PEEK : rest_state ());
        }

        static void cancel (ref uint source) {
            if (source != 0) {
                Source.remove (source);
                source = 0;
            }
        }

        void pointer_entered () {
            pointer_inside = true;
            cut_intro ();
            cancel (ref exit_source);
            if (state == IslandState.EXPANDED) {
                return;
            }
            move_to (IslandState.PEEK);
            if (model.settings.open_on_hover && hover_source == 0) {
                hover_source = Timeout.add (650, () => {
                    hover_source = 0;
                    if (state == IslandState.PEEK && pointer_inside) {
                        open ();
                    }
                    return Source.REMOVE;
                });
            }
        }

        void pointer_left () {
            pointer_inside = false;
            cancel (ref hover_source);
            if (state == IslandState.PEEK) {
                move_to (rest_state ());
            } else if (state == IslandState.EXPANDED && !is_held ()) {
                schedule_exit ();
            }
        }

        void schedule_exit () {
            cancel (ref exit_source);
            exit_source = Timeout.add (350, () => {
                exit_source = 0;
                if (state == IslandState.EXPANDED && !pointer_inside && !is_held ()) {
                    move_to (rest_state ());
                }
                return Source.REMOVE;
            });
        }

        void on_model_changed () {
            var current = model.current ();
            if (current != null || state != IslandState.HIDDEN) {
                shown = current;
            }
            compact.accent = accent ();
            if (state == IslandState.HIDDEN || state == IslandState.COLLAPSED) {
                move_to (rest_state ());
            } else {
                update_targets ();
            }
            // A request answered elsewhere lets the island close once the pointer is away.
            if (state == IslandState.EXPANDED && !pointer_inside && !is_held () && exit_source == 0) {
                schedule_exit ();
            }
            update_animation_timer ();
            queue_draw ();
        }

        Gdk.RGBA accent () {
            return expanded.accent ();
        }

        /* Equalizer bars and spinners move a few times a second while they are on show, and never otherwise. */
        void update_animation_timer () {
            bool wanted = !frozen && !reduce_motion () && shown != null && ((!) shown).is_animated ()
                && (state == IslandState.COLLAPSED || state == IslandState.PEEK);
            if (wanted && animation_source == 0) {
                animation_source = Timeout.add (100, () => {
                    queue_draw ();
                    return Source.CONTINUE;
                });
            } else if (!wanted) {
                cancel (ref animation_source);
            }
        }

        /* --------------------------------------------------------------------------------------------------------- */
        /* Intro */

        /* The intro holds the closed island, swollen: activities wait until it settles back. */
        bool intro_holds () {
            return intro_start >= 0 && intro_swelled && !intro_tucked;
        }

        double intro_time () {
            return intro_start < 0 ? -1 : (get_monotonic_time () - intro_start) / 1000000.0;
        }

        /* Plays the intro, with its chime unless `sound` is false. Not while the island is open. */
        public void play_intro (bool sound) {
            if (intro_start >= 0 || state == IslandState.EXPANDED) {
                return;
            }
            // Without animations, only the chime.
            if (reduce_motion ()) {
                if (sound) {
                    chime = new Intro.Chime ();
                    Timeout.add (3500, () => {
                        chime = null;
                        return Source.REMOVE;
                    });
                }
                return;
            }
            intro_start = get_monotonic_time ();
            intro_swelled = false;
            intro_tucked = false;
            update_envelope ();
            if (sound) {
                chime = new Intro.Chime ();
            }
            intro_tick = add_tick_callback ((widget, clock) => intro_frame ());
        }

        bool intro_frame () {
            double t = intro_time ();
            if (t < 0) {
                intro_tick = 0;
                return Source.REMOVE;
            }
            if (!intro_swelled && t >= IntroScore.SWELL) {
                intro_swelled = true;
                move_to (IslandState.COLLAPSED);
                update_targets ();
            }
            if (!intro_tucked && t >= IntroScore.TUCK) {
                intro_tucked = true;
                move_to (rest_state ());
                update_targets ();
            }
            queue_draw ();
            if (t >= IntroScore.END) {
                intro_tick = 0;
                finish_intro ();
                return Source.REMOVE;
            }
            return Source.CONTINUE;
        }

        /* Ends the intro at once: the pointer came to the island, or something opened it. */
        void cut_intro () {
            if (intro_start < 0) {
                return;
            }
            if (intro_tick != 0) {
                remove_tick_callback (intro_tick);
                intro_tick = 0;
            }
            finish_intro ();
        }

        void finish_intro () {
            bool held = intro_holds ();
            intro_start = -1;
            intro_swelled = false;
            intro_tucked = false;
            // The chime rings on a little after the picture; it lets go once it has played.
            Timeout.add (900, () => {
                chime = null;
                return Source.REMOVE;
            });
            if (held) {
                move_to (rest_state ());
            }
            update_targets ();
            update_envelope ();
            queue_draw ();
        }

        /* --------------------------------------------------------------------------------------------------------- */
        /* Geometry and springs */

        static int level (IslandState state) {
            switch (state) {
            case IslandState.HIDDEN: return 0;
            case IslandState.EXPANDED: return 2;
            default: return 1;
            }
        }

        static IslandState state_of_level (int value) {
            switch (value) {
            case 0: return IslandState.HIDDEN;
            case 2: return IslandState.EXPANDED;
            default: return IslandState.COLLAPSED;
            }
        }

        Frame target_frame (IslandState for_state) {
            double cx = envelope_width / 2.0;
            double width = intro_holds () ? INTRO_WIDTH : compact.width_for (shown);
            return Geometry.frame (for_state, cx, width, model.settings.island_size (), gap);
        }

        public Frame current_frame () {
            return Frame (get_width () / 2.0, top_spring.value, width_spring.value, height_spring.value, radius_spring.value);
        }

        void update_targets () {
            var target = target_frame (state);
            Motion motion;
            switch (state) {
            case IslandState.EXPANDED: motion = Motion.opening (); break;
            case IslandState.PEEK: motion = Motion.peeking (); break;
            default: motion = Motion.closing (); break;
            }
            width_spring.animate_to (target.width, motion);
            height_spring.animate_to (target.height, motion);
            top_spring.animate_to (target.y, motion);
            radius_spring.animate_to (target.radius, motion);
            presence.animate_to (state == IslandState.HIDDEN ? 0 : 1, Motion (state == IslandState.HIDDEN ? 0.3 : 0.2, 0));
            bool open = state == IslandState.EXPANDED;
            open_alpha.animate_to (open ? 1 : 0, open ? Motion (0.45, 0) : Motion (0.16, 0));
            compact_alpha.animate_to (open ? 0 : 1, open ? Motion (0.14, 0) : Motion (0.35, 0));
            update_envelope ();
            start_ticking ();
        }

        Spring[] springs () {
            return { width_spring, height_spring, top_spring, radius_spring, presence, open_alpha, compact_alpha };
        }

        void start_ticking () {
            if (tick_id != 0) {
                return;
            }
            if (frozen || reduce_motion () || !get_mapped ()) {
                foreach (var spring in springs ()) {
                    spring.jump_to (spring.target);
                }
                settled ();
                return;
            }
            last_frame = 0;
            tick_id = add_tick_callback ((widget, clock) => {
                int64 now = clock.get_frame_time ();
                double dt = last_frame == 0 ? 1.0 / 60 : (now - last_frame) / 1000000.0;
                last_frame = now;
                bool moving = false;
                foreach (var spring in springs ()) {
                    if (spring.step (dt)) {
                        moving = true;
                    }
                }
                input_changed ();
                queue_draw ();
                if (!moving) {
                    tick_id = 0;
                    settled ();
                    return Source.REMOVE;
                }
                return Source.CONTINUE;
            });
        }

        public override void map () {
            base.map ();
            // The surface's first frame: a layer surface mapped with nothing moving would otherwise wait for one.
            queue_resize ();
            // Springs asked to move before the island was on screen get there now.
            if (tick_id == 0) {
                start_ticking ();
            }
        }

        void settled () {
            visual = state;
            if (state != IslandState.EXPANDED && open_alpha.value <= 0.001) {
                expanded.set_child_visible (false);
            }
            if (state == IslandState.HIDDEN) {
                shown = model.current ();
            }
            update_envelope ();
            input_changed ();
            queue_draw ();
        }

        /* The surface the island needs: the largest of the state it goes to and the one it still shows. */
        void update_envelope () {
            int w, h;
            // The intro's waves need the room of the open island.
            var largest = intro_start >= 0 ? IslandState.EXPANDED : state_of_level (int.max (level (state), level (visual)));
            Geometry.envelope (largest, model.settings.island_size (), gap, out w, out h);
            if (w != envelope_width || h != envelope_height) {
                envelope_width = w;
                envelope_height = h;
                queue_resize ();
                envelope_changed ();
            }
        }

        /* Where the pointer is taken, in the surface: the island and the space above it, or the thin strip at the top
         * edge when the island is hidden. Elsewhere clicks go to the windows below. */
        public Cairo.RectangleInt input_rect () {
            var f = current_frame ();
            if (state == IslandState.HIDDEN && presence.value < 0.05) {
                int width = (int) Geometry.STRIP_WIDTH;
                return { (get_width () - width) / 2, 0, width, (int) Geometry.STRIP_HEIGHT };
            }
            int left = (int) Math.floor (f.left ());
            int right = (int) Math.ceil (f.right ());
            int bottom = (int) Math.ceil (f.bottom ());
            return { left, 0, right - left, bottom };
        }

        /* --------------------------------------------------------------------------------------------------------- */
        /* Layout and drawing */

        public override Gtk.SizeRequestMode get_request_mode () {
            return Gtk.SizeRequestMode.CONSTANT_SIZE;
        }

        public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural,
                                      out int minimum_baseline, out int natural_baseline) {
            minimum = natural = orientation == Gtk.Orientation.HORIZONTAL ? envelope_width : envelope_height;
            minimum_baseline = natural_baseline = -1;
            // The open pages measure themselves even while hidden, so they are ready.
            int child_min, child_nat, b1, b2;
            expanded.measure (orientation, -1, out child_min, out child_nat, out b1, out b2);
        }

        public override void size_allocate (int width, int height, int baseline) {
            var size = model.settings.island_size ();
            int w = (int) size.open_width (), h = (int) size.open_height ();
            var transform = new Gsk.Transform ().translate (Graphene.Point ().init ((width - w) / 2, (float) gap));
            expanded.allocate (w, h, -1, transform);
            input_changed ();
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            double alpha = presence.value.clamp (0, 1);
            double intro = intro_time ();
            var rest = Geometry.frame (IslandState.COLLAPSED, get_width () / 2.0, Geometry.REST_WIDTH, model.settings.island_size (), gap);
            var swollen = Geometry.frame (IslandState.COLLAPSED, get_width () / 2.0, INTRO_WIDTH, model.settings.island_size (), gap);
            if (intro >= 0) {
                Intro.draw_back (snapshot, intro, rest, swollen, accent (), get_width (), get_height ());
            }
            if (alpha <= 0.005) {
                if (intro >= 0) {
                    Intro.draw_front (snapshot, intro, rest, accent (), get_width (), get_height ());
                    return;
                }
                // A surface with nothing drawn gets no buffer, and the compositor would neither show it nor give it the
                // pointer: the hidden island keeps a strip one step away from transparent.
                var faint = Gdk.RGBA ();
                faint.alpha = 1.0f / 255;
                snapshot.append_color (faint, Graphene.Rect ().init (0, 0, get_width (), get_height ()));
                return;
            }
            var f = current_frame ();
            double radius = f.effective_radius ();
            var size = model.settings.island_size ();
            double openness = ((f.height - Geometry.PILL_HEIGHT) / (size.open_height () - Geometry.PILL_HEIGHT)).clamp (0, 1);
            var bounds = Graphene.Rect ().init ((float) f.left (), (float) f.y, (float) f.width, (float) f.height);
            var rounded = Gsk.RoundedRect ();
            rounded.init_from_rect (bounds, (float) radius);

            // A soft shadow under the open island, so it reads on any wallpaper.
            if (openness > 0.01) {
                var shade = Gdk.RGBA ();
                shade.alpha = (float) (0.42 * openness * alpha);
                snapshot.append_outset_shadow (rounded, shade, 0, 10, 0, 26);
            }

            var area = Graphene.Rect ().init ((float) f.left () - 1, (float) f.y - 1, (float) f.width + 2, (float) f.height + 2);
            var cr = snapshot.append_cairo (area);
            Geometry.outline (f, new CairoSink (cr));
            var night = Rgba.named_night ();
            cr.set_source_rgba (night.red, night.green, night.blue, alpha);
            cr.fill_preserve ();
            // A hairline keeps the edge visible on a dark desktop.
            cr.set_source_rgba (1, 1, 1, 0.075 * alpha);
            cr.set_line_width (1);
            cr.stroke ();

            snapshot.push_rounded_clip (rounded);
            if (intro_holds () || (intro >= IntroScore.SWELL && intro < IntroScore.TUCK)) {
                // The intro's own wings while it holds the island, fading in as it swells.
                double shown_alpha = ((intro - IntroScore.SWELL) / 0.2).clamp (0, 1) * (1 - ((intro - (IntroScore.TUCK - 0.2)) / 0.2).clamp (0, 1));
                Intro.draw_wings (snapshot, intro, f, accent (), shown_alpha * alpha);
            } else {
                compact.draw (snapshot, shown, f, compact_alpha.value.clamp (0, 1) * alpha);
            }
            if (expanded.get_child_visible () && open_alpha.value > 0.01) {
                snapshot.push_opacity (open_alpha.value.clamp (0, 1) * alpha);
                snapshot_child (expanded, snapshot);
                snapshot.pop ();
            }
            snapshot.pop ();
            if (intro >= 0) {
                Intro.draw_front (snapshot, intro, rest, accent (), get_width (), get_height ());
            }
        }
    }
}
