/* The tools page: a timer that counts down in the wings, keep awake, and the clipboard history. */

namespace Col {
    public class ToolsPage : Gtk.Box {
        Model model;
        Gtk.Stack timer_stack;
        Gtk.Label countdown;
        Gtk.Switch awake;
        Gtk.Box clips;
        Gtk.Stack clip_stack;
        bool updating = false;

        public ToolsPage (Model model) {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 18);
            this.model = model;
            margin_start = 20;
            margin_end = 16;
            margin_top = 2;
            margin_bottom = 14;
            homogeneous = true;

            // Timer and keep awake.
            var left = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            left.append (heading (_("Timer")));
            timer_stack = new Gtk.Stack ();
            timer_stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
            var presets = new Gtk.FlowBox ();
            presets.selection_mode = Gtk.SelectionMode.NONE;
            presets.max_children_per_line = 3;
            presets.min_children_per_line = 3;
            presets.column_spacing = 6;
            presets.row_spacing = 6;
            presets.homogeneous = true;
            int[] minutes = { 1, 3, 5, 10, 25, 45 };
            foreach (var amount in minutes) {
                var chip = new Gtk.Button.with_label (_("%d min").printf (amount));
                chip.add_css_class ("col-chip");
                chip.focus_on_click = false;
                var seconds = amount * 60;
                chip.clicked.connect (() => model.timer.start (seconds));
                presets.append (chip);
            }
            timer_stack.add_named (presets, "presets");
            var running = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            countdown = new Gtk.Label ("0:00");
            countdown.add_css_class ("col-countdown");
            countdown.hexpand = true;
            countdown.xalign = 0;
            var more = new Gtk.Button.with_label (_("+1 min"));
            more.add_css_class ("col-chip");
            more.focus_on_click = false;
            more.valign = Gtk.Align.CENTER;
            more.clicked.connect (() => model.timer.add (60));
            var stop = glyph_button ("close", _("Cancel the timer"), 14);
            stop.add_css_class ("col-round");
            stop.valign = Gtk.Align.CENTER;
            stop.clicked.connect (() => model.timer.cancel ());
            running.append (countdown);
            running.append (more);
            running.append (stop);
            timer_stack.add_named (running, "running");
            left.append (timer_stack);

            var spacer = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            spacer.vexpand = true;
            left.append (spacer);
            var awake_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var cup = new Glyphs.Icon ("cup", 18);
            cup.valign = Gtk.Align.CENTER;
            awake_row.append (cup);
            var awake_label = new Gtk.Label (_("Keep awake"));
            awake_label.add_css_class ("col-row-title");
            awake_label.hexpand = true;
            awake_label.xalign = 0;
            awake_row.append (awake_label);
            awake = new Gtk.Switch ();
            awake.valign = Gtk.Align.CENTER;
            awake.focus_on_click = false;
            awake.notify["active"].connect (() => {
                if (!updating) {
                    model.awake_requested (awake.active);
                }
            });
            awake_row.append (awake);
            left.append (awake_row);
            append (left);

            // Clipboard.
            var right = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            right.append (heading (_("Clipboard")));
            clip_stack = new Gtk.Stack ();
            clip_stack.vexpand = true;
            clips = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            var scroller = new Gtk.ScrolledWindow ();
            scroller.child = clips;
            scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroller.vexpand = true;
            clip_stack.add_named (scroller, "list");
            var nothing = new Gtk.Label (_("Nothing copied yet"));
            nothing.add_css_class ("col-hint");
            nothing.wrap = true;
            nothing.valign = Gtk.Align.CENTER;
            clip_stack.add_named (nothing, "empty");
            var off = new Gtk.Label (_("Clipboard history is off, or this desktop does not share the clipboard with Col."));
            off.add_css_class ("col-hint");
            off.wrap = true;
            off.max_width_chars = 24;
            off.valign = Gtk.Align.CENTER;
            clip_stack.add_named (off, "off");
            right.append (clip_stack);
            append (right);

            model.tools_changed.connect (update);
            update ();
        }

        static Gtk.Label heading (string text) {
            var label = new Gtk.Label (text);
            label.add_css_class ("col-heading");
            label.xalign = 0;
            return label;
        }

        Gtk.Widget clip_row (string text) {
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            row.add_css_class ("col-clip");
            var button = new Gtk.Button ();
            button.add_css_class ("col-clip-text");
            button.focus_on_click = false;
            button.hexpand = true;
            var label = new Gtk.Label (text.strip ().replace ("\n", " ⏎ "));
            label.xalign = 0;
            label.ellipsize = Pango.EllipsizeMode.END;
            label.max_width_chars = 1;
            label.single_line_mode = true;
            button.child = label;
            button.tooltip_text = _("Copy again");
            button.clicked.connect (() => model.clipboard.copy (text));
            row.append (button);
            bool pinned = model.clipboard.is_pinned (text);
            var pin = glyph_button (pinned ? "pin-filled" : "pin", pinned ? _("Unpin") : _("Pin"), 14);
            pin.add_css_class ("col-pin");
            if (pinned) {
                pin.add_css_class ("pinned");
            }
            pin.clicked.connect (() => model.clipboard.toggle_pin (text));
            row.append (pin);
            return row;
        }

        public void update () {
            updating = true;
            awake.active = model.awake;
            updating = false;
            if (model.timer.running ()) {
                countdown.label = TimerTool.format (model.timer.remaining ());
                timer_stack.visible_child_name = "running";
            } else {
                timer_stack.visible_child_name = "presets";
            }
            Gtk.Widget? child;
            while ((child = clips.get_first_child ()) != null) {
                clips.remove ((!) child);
            }
            var shown = model.clipboard.shown ();
            foreach (var text in shown) {
                clips.append (clip_row (text));
            }
            if (shown.length > 0) {
                clip_stack.visible_child_name = "list";
            } else if (!model.settings.clipboard_history || !model.clipboard.available ()) {
                clip_stack.visible_child_name = "off";
            } else {
                clip_stack.visible_child_name = "empty";
            }
        }
    }
}
