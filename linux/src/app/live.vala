/* The agents and activities page: a permission request with Allow and Deny when an agent asks, otherwise every agent
 * session and every activity scripts pushed. */

namespace Col {
    class AgentTile : Gtk.Widget {
        public CodingAgent agent;
        public bool waiting;

        public AgentTile (CodingAgent agent, int size) {
            this.agent = agent;
            set_size_request (size, size);
            valign = Gtk.Align.CENTER;
            can_target = false;
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            double size = double.min (get_width (), get_height ());
            var cr = snapshot.append_cairo (Graphene.Rect ().init (0, 0, get_width () + 2, get_height () + 2));
            Glyphs.agent_tile (cr, agent, 0, 0, size, 1);
            if (waiting) {
                cr.set_source_rgba (1, 0.62, 0.04, 1);
                cr.arc (size - 2, 3, 4, 0, 2 * Math.PI);
                cr.fill ();
            }
        }
    }

    class ProgressLine : Gtk.Widget {
        public double fraction;
        public Rgba tint;

        construct {
            set_size_request (40, 4);
            valign = Gtk.Align.CENTER;
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            var cr = snapshot.append_cairo (Graphene.Rect ().init (0, 0, get_width (), get_height ()));
            Glyphs.rounded (cr, 0, 0, get_width (), get_height (), 2);
            cr.set_source_rgba (1, 1, 1, 0.18);
            cr.fill ();
            Glyphs.rounded (cr, 0, 0, double.max (4, get_width () * fraction), get_height (), 2);
            cr.set_source_rgba (tint.red, tint.green, tint.blue, 1);
            cr.fill ();
        }
    }

    /* The request of an agent: who asks, what for, the whole command, and the answer. */
    class PermissionCard : Gtk.Box {
        Model model;
        PendingRequest? request;
        AgentTile tile;
        Gtk.Label project;
        Gtk.Label badge;
        Gtk.Label summary;
        Gtk.Label command;
        Gtk.ScrolledWindow command_box;
        Gtk.Button allow;
        Gtk.Button deny;
        Gtk.Label note;

        public PermissionCard (Model model) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 8);
            this.model = model;
            add_css_class ("col-card");

            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            tile = new AgentTile (CodingAgent.CLAUDE, 22);
            tile.waiting = true;
            header.append (tile);
            project = new Gtk.Label ("");
            project.add_css_class ("col-title");
            project.ellipsize = Pango.EllipsizeMode.END;
            project.max_width_chars = 18;
            header.append (project);
            badge = new Gtk.Label ("");
            badge.add_css_class ("col-badge");
            header.append (badge);
            summary = new Gtk.Label ("");
            summary.add_css_class ("col-subtitle");
            summary.ellipsize = Pango.EllipsizeMode.END;
            summary.max_width_chars = 1;
            summary.hexpand = true;
            summary.xalign = 0;
            header.append (summary);
            append (header);

            command = new Gtk.Label ("");
            command.add_css_class ("col-command-text");
            command.xalign = 0;
            command.yalign = 0;
            command.wrap = true;
            command.wrap_mode = Pango.WrapMode.WORD_CHAR;
            command.selectable = true;
            command.can_focus = false;
            command_box = new Gtk.ScrolledWindow ();
            command_box.child = command;
            command_box.hscrollbar_policy = Gtk.PolicyType.NEVER;
            command_box.add_css_class ("col-command");
            append (command_box);

            var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            allow = new Gtk.Button.with_label (_("Allow"));
            allow.add_css_class ("col-allow");
            allow.focus_on_click = false;
            deny = new Gtk.Button.with_label (_("Deny"));
            deny.add_css_class ("col-deny");
            deny.focus_on_click = false;
            var terminal = new Gtk.Button.with_label (_("Answer in terminal"));
            terminal.add_css_class ("col-link");
            terminal.focus_on_click = false;
            terminal.hexpand = true;
            terminal.halign = Gtk.Align.END;
            allow.clicked.connect (() => answer (Decision.ALLOW));
            deny.clicked.connect (() => answer (Decision.DENY));
            terminal.clicked.connect (() => answer (Decision.ASK));
            buttons.append (allow);
            buttons.append (deny);
            buttons.append (terminal);
            append (buttons);

            note = new Gtk.Label (_("Too long to check here: answer in the terminal."));
            note.add_css_class ("col-hint");
            note.xalign = 0;
            note.visible = false;
            append (note);
        }

        void answer (Decision decision) {
            if (request != null) {
                model.agents.decide (request.id, decision);
            }
        }

        public void show_request (PendingRequest request) {
            this.request = request;
            tile.agent = request.agent;
            tile.queue_draw ();
            project.label = request.project;
            badge.label = request.has_agent ? request.agent.display_name () : _("Agent");
            summary.label = request.summary;
            var detail = request.detail;
            command_box.visible = detail != null;
            command.label = detail != null ? detail.shown : "";
            // As tall as the command when the card shows it whole; three lines that scroll when it is longer.
            bool fits = detail == null || detail.fits_card;
            command_box.vscrollbar_policy = fits ? Gtk.PolicyType.NEVER : Gtk.PolicyType.AUTOMATIC;
            command_box.propagate_natural_height = true;
            command_box.max_content_height = fits ? -1 : 14 + 18 * RequestDetail.LINES;
            bool can = request.can_allow ();
            allow.sensitive = can;
            note.visible = !can;
        }
    }

    public class LivePage : Gtk.Box {
        Model model;
        Gtk.Stack stack;
        PermissionCard card;
        Gtk.Box list;
        Gtk.Box empty;

        public LivePage (Model model) {
            this.model = model;
            stack = new Gtk.Stack ();
            stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
            stack.hexpand = true;
            stack.vexpand = true;
            append (stack);
            card = new PermissionCard (model);
            card.margin_start = 16;
            card.margin_end = 16;
            card.margin_top = 4;
            card.margin_bottom = 14;
            card.valign = Gtk.Align.CENTER;
            stack.add_named (card, "request");

            list = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            list.margin_start = 20;
            list.margin_end = 20;
            list.margin_top = 4;
            list.margin_bottom = 12;
            var scroller = new Gtk.ScrolledWindow ();
            scroller.child = list;
            scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
            stack.add_named (scroller, "list");

            empty = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            empty.valign = Gtk.Align.CENTER;
            empty.halign = Gtk.Align.CENTER;
            var title = new Gtk.Label (_("No agent at work"));
            title.add_css_class ("col-title");
            var hint = new Gtk.Label (_("Connect Claude Code or Codex in Settings, or push your own activities with colctl."));
            hint.add_css_class ("col-hint");
            hint.wrap = true;
            hint.max_width_chars = 42;
            hint.justify = Gtk.Justification.CENTER;
            empty.append (title);
            empty.append (hint);
            stack.add_named (empty, "empty");

            model.agents_changed.connect (update);
            update ();
        }

        Gtk.Widget session_row (AgentSession session) {
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            row.add_css_class ("col-row");
            CodingAgent agent;
            if (!CodingAgent.from_name (session.agent, out agent)) {
                agent = CodingAgent.CLAUDE;
            }
            var tile = new AgentTile (agent, 26);
            tile.waiting = session.state == SessionState.WAITING;
            row.append (tile);
            var texts = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            texts.hexpand = true;
            var name = new Gtk.Label (session.project);
            name.add_css_class ("col-row-title");
            name.xalign = 0;
            name.ellipsize = Pango.EllipsizeMode.END;
            var line = new Gtk.Label (state_text (session));
            line.add_css_class ("col-subtitle");
            line.xalign = 0;
            line.ellipsize = Pango.EllipsizeMode.END;
            line.max_width_chars = 1;
            texts.append (name);
            texts.append (line);
            row.append (texts);
            return row;
        }

        static string state_text (AgentSession session) {
            var agent = session.agent ?? "";
            string state;
            switch (session.state) {
            case SessionState.WORKING:
                state = session.detail ?? _("Working");
                break;
            case SessionState.WAITING:
                state = session.detail ?? _("Waiting for you");
                break;
            case SessionState.DONE:
                state = _("Done");
                break;
            default:
                state = _("Idle");
                break;
            }
            return agent != "" ? "%s · %s".printf (agent, state) : state;
        }

        Gtk.Widget activity_row (CustomActivities.Entry entry) {
            var request = entry.request;
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            row.add_css_class ("col-row");
            var icon = new Glyphs.Icon (entry.finished ? "check-circle" : Glyphs.resolve (request.symbol), 22);
            var tint = entry.finished ? Rgba.named_green () : request.resolved_tint ();
            icon.tint = Glyphs.rgba (tint);
            icon.valign = Gtk.Align.CENTER;
            row.append (icon);
            var texts = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            texts.hexpand = true;
            var name = new Gtk.Label (request.title ?? request.id);
            name.add_css_class ("col-row-title");
            name.xalign = 0;
            name.ellipsize = Pango.EllipsizeMode.END;
            texts.append (name);
            if (request.subtitle != null) {
                var sub = new Gtk.Label ((!) request.subtitle);
                sub.add_css_class ("col-subtitle");
                sub.xalign = 0;
                sub.ellipsize = Pango.EllipsizeMode.END;
                sub.max_width_chars = 1;
                texts.append (sub);
            }
            if (request.has_progress && !entry.finished) {
                var bar = new ProgressLine ();
                bar.fraction = request.progress;
                bar.tint = tint;
                bar.margin_top = 3;
                texts.append (bar);
            }
            row.append (texts);
            if (request.text != null && request.text != "") {
                var text = new Gtk.Label ((!) request.text);
                text.add_css_class ("col-subtitle");
                row.append (text);
            }
            return row;
        }

        public void update () {
            var request = model.agents.first_request ();
            if (request != null) {
                card.show_request ((!) request);
                stack.visible_child_name = "request";
                return;
            }
            Gtk.Widget? child;
            while ((child = list.get_first_child ()) != null) {
                list.remove ((!) child);
            }
            int count = 0;
            foreach (var session in model.agents.board.ordered ()) {
                list.append (session_row (session));
                count++;
            }
            foreach (var entry in model.custom.entries) {
                list.append (activity_row (entry));
                count++;
            }
            stack.visible_child_name = count > 0 ? "list" : "empty";
        }
    }
}
