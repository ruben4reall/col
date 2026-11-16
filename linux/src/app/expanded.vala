/* The open island: a row of page tabs and the system's state at the top, then the page. */

namespace Col {
    public Gtk.Button glyph_button (string glyph, string tooltip, int size = 18) {
        var button = new Gtk.Button ();
        button.child = new Glyphs.Icon (glyph, size);
        button.add_css_class ("col-glyph");
        button.tooltip_text = tooltip;
        button.focus_on_click = false;
        return button;
    }

    /* A widget that only reads a colour from the CSS: the desktop's accent, as libadwaita gives it. */
    class AccentProbe : Gtk.Widget {
        construct {
            add_css_class ("col-accent");
            can_target = false;
        }

        public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural,
                                      out int minimum_baseline, out int natural_baseline) {
            minimum = natural = 0;
            minimum_baseline = natural_baseline = -1;
        }
    }

    /* The battery, as the top bar shows it. */
    class BatteryIcon : Gtk.Widget {
        public double level = 1;
        public bool charging = false;

        construct {
            set_size_request (30, 16);
            can_target = false;
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            var cr = snapshot.append_cairo (Graphene.Rect ().init (0, 0, get_width (), get_height ()));
            CompactRenderer.draw_battery (cr, 1, get_height () / 2.0, level, charging, 1);
        }
    }

    public class ExpandedView : Gtk.Box {
        Model model;
        Gtk.Stack stack;
        Gtk.Button[] tabs = {};
        string[] pages = { "music", "live", "tools" };
        Gtk.Label battery_label;
        BatteryIcon battery_icon;
        Gtk.Box battery_box;
        AccentProbe probe;
        Glyphs.Icon live_icon;
        public MusicPage music;
        public LivePage live;
        public ToolsPage tools;

        public ExpandedView (Model model) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.model = model;
            add_css_class ("col-island-content");
            overflow = Gtk.Overflow.HIDDEN;

            var bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
            bar.add_css_class ("col-top-bar");
            string[] glyphs = { "note", "sparkle", "grid" };
            string[] names = { _("Music"), _("Agents and activities"), _("Tools") };
            for (int i = 0; i < 3; i++) {
                var button = glyph_button (glyphs[i], names[i], 16);
                button.add_css_class ("col-tab");
                var page = pages[i];
                button.clicked.connect (() => show_page (page));
                bar.append (button);
                tabs += button;
            }
            live_icon = (Glyphs.Icon) tabs[1].child;
            probe = new AccentProbe ();
            bar.append (probe);
            var spacer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append (spacer);
            battery_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            battery_label = new Gtk.Label ("");
            battery_label.add_css_class ("col-battery-label");
            battery_icon = new BatteryIcon ();
            battery_icon.valign = Gtk.Align.CENTER;
            battery_box.append (battery_label);
            battery_box.append (battery_icon);
            battery_box.margin_end = 6;
            battery_box.valign = Gtk.Align.CENTER;
            bar.append (battery_box);
            var gear = glyph_button ("gear", _("Settings"), 16);
            gear.clicked.connect (() => model.settings_requested ());
            bar.append (gear);
            append (bar);

            stack = new Gtk.Stack ();
            stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
            stack.transition_duration = 160;
            stack.vexpand = true;
            stack.hexpand = true;
            music = new MusicPage (model);
            live = new LivePage (model);
            tools = new ToolsPage (model);
            stack.add_named (music, "music");
            stack.add_named (live, "live");
            stack.add_named (tools, "tools");
            append (stack);
            show_page ("music");

            model.battery_changed.connect (update_battery);
            model.agents_changed.connect (update_tabs);
            update_battery ();
        }

        public Gdk.RGBA accent () {
            return probe.get_color ();
        }

        public void show_page (string name) {
            stack.visible_child_name = name;
            update_tabs ();
        }

        public string current_page () {
            return stack.visible_child_name;
        }

        void update_tabs () {
            for (int i = 0; i < tabs.length; i++) {
                if (pages[i] == stack.visible_child_name) {
                    tabs[i].add_css_class ("selected");
                } else {
                    tabs[i].remove_css_class ("selected");
                }
            }
            if (model.agents.pending.length > 0) {
                tabs[1].add_css_class ("col-attention");
            } else {
                tabs[1].remove_css_class ("col-attention");
            }
        }

        void update_battery () {
            battery_box.visible = model.battery_present;
            battery_label.label = "%d%%".printf ((int) Math.round (model.battery_level * 100));
            battery_icon.level = model.battery_level;
            battery_icon.charging = model.battery_charging;
            battery_icon.queue_draw ();
        }

        /* The island opened: pages that show time start their clocks. */
        public void opened () {
            // The page of what the closed island showed: the song, the agents, the timer.
            var current = model.current ();
            if (model.agents.pending.length > 0) {
                show_page ("live");
            } else if (current != null) {
                var id = current.id;
                if (id == "media") {
                    show_page ("music");
                } else if (id == "agents" || id.has_prefix ("api.")) {
                    show_page ("live");
                } else if (id == "timer" || id == "awake") {
                    show_page ("tools");
                }
            }
            music.set_active (true);
        }

        public void closed () {
            music.set_active (false);
        }
    }
}
