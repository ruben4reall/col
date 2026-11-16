/* Col's settings: General, Music and lyrics, Agents, About. A libadwaita preferences dialog in a window of its own. */

namespace Col {
    public class Preferences : Adw.PreferencesDialog {
        Settings settings;
        Adw.ActionRow[] agent_rows = {};
        Gtk.Button[] agent_buttons = {};

        public Preferences (Settings settings, bool welcome) {
            this.settings = settings;
            title = _("Col Settings");
            search_enabled = false;
            add (general_page (welcome));
            add (music_page ());
            add (agents_page ());
            add (about_page ());
        }

        static bool is_kde () {
            var desktop = Environment.get_variable ("XDG_CURRENT_DESKTOP") ?? "";
            return desktop.down ().contains ("kde");
        }

        Adw.SwitchRow switch_row (string title, string? subtitle, string property) {
            var row = new Adw.SwitchRow ();
            row.title = title;
            if (subtitle != null) {
                row.subtitle = subtitle;
            }
            settings.bind_property (property, row, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
            return row;
        }

        Adw.PreferencesPage general_page (bool welcome) {
            var page = new Adw.PreferencesPage ();
            page.title = _("General");
            page.icon_name = "preferences-system-symbolic";

            if (welcome) {
                var hello = new Adw.PreferencesGroup ();
                hello.title = _("Welcome to Col");
                hello.description = _("The island lives at the top of your screen. Rest the pointer on the top edge, in the middle, to bring it out; click it to open it. Everything below can change later, here.");
                page.add (hello);
            }

            var island = new Adw.PreferencesGroup ();
            island.title = _("Island");
            var login = new Adw.SwitchRow ();
            login.title = _("Open Col at login");
            login.active = Settings.autostart_enabled ();
            login.notify["active"].connect (() => Settings.set_autostart (login.active));
            island.add (login);
            island.add (switch_row (_("Show the island at rest"),
                _("Off, it appears only when something happens. The top edge of the screen always brings it out."), "visible-at-rest"));
            island.add (switch_row (_("Open on hover"), _("Rest the pointer on the island to open it. A click always does."), "open-on-hover"));

            var size = new Adw.ComboRow ();
            size.title = _("Size of the open island");
            size.model = new Gtk.StringList ({ _("Compact"), _("Standard"), _("Large") });
            string[] keys = { "compact", "standard", "large" };
            for (int i = 0; i < keys.length; i++) {
                if (keys[i] == settings.size) {
                    size.selected = i;
                }
            }
            size.notify["selected"].connect (() => settings.size = keys[size.selected]);
            island.add (size);

            var screen = new Adw.ComboRow ();
            screen.title = _("Screen");
            var names = new Gtk.StringList (null);
            names.append (_("Automatic"));
            var connectors = new GenericArray<string> ();
            connectors.add ("");
            var display = Gdk.Display.get_default ();
            if (display != null) {
                var monitors = display.get_monitors ();
                for (uint i = 0; i < monitors.get_n_items (); i++) {
                    var monitor = (Gdk.Monitor) monitors.get_item (i);
                    var connector = monitor.connector ?? "";
                    var label = monitor.description ?? monitor.model ?? connector;
                    names.append (connector != "" && label != connector ? "%s (%s)".printf (label, connector) : label);
                    connectors.add (connector);
                    if (connector != "" && connector == settings.monitor) {
                        screen.selected = i + 1;
                    }
                }
            }
            screen.model = names;
            screen.notify["selected"].connect (() => {
                if (screen.selected < connectors.length) {
                    settings.monitor = connectors[screen.selected];
                }
            });
            island.add (screen);
            island.add (switch_row (_("Below the top panel"),
                _("Leaves a panel at the top of the screen uncovered. Not on GNOME, where the island always sits below the top bar."),
                "below-panels"));
            page.add (island);

            var system = new Adw.PreferencesGroup ();
            system.title = _("System");
            system.add (switch_row (_("Volume"), _("A gauge in the island when the volume changes."), "volume-display"));
            if (is_kde ()) {
                var osd = new Adw.ActionRow ();
                osd.title = _("Plasma shows its own volume display too");
                osd.subtitle = _("To keep only Col's, open the settings of the Audio Volume widget in your panel and turn off its visual feedback for volume changes.");
                osd.subtitle_lines = 0;
                system.add (osd);
            }
            system.add (switch_row (_("Charging and low battery"), _("Plugging in and a low battery show in the island."), "battery-display"));
            system.add (switch_row (_("Clipboard history"),
                _("Kept in memory only, except the copies you pin, which are saved in Col's settings. Copies from password managers are skipped."),
                "clipboard-history"));
            page.add (system);
            return page;
        }

        Adw.PreferencesPage music_page () {
            var page = new Adw.PreferencesPage ();
            page.title = _("Music");
            page.icon_name = "audio-x-generic-symbolic";

            var group = new Adw.PreferencesGroup ();
            group.title = _("Music and lyrics");
            group.description = _("The song playing comes from any player that speaks MPRIS: Spotify, your browser, VLC and most others. Lyrics come from LRCLIB, an open database written by its users. Col sends it only the title, the artist, the album and the length of the track, and keeps the answer on this computer, so each song is asked once.");
            group.add (switch_row (_("Synced lyrics"), _("The words of the song beside the player, line by line."), "lyrics"));
            group.add (switch_row (_("The line being sung in the closed island"), null, "lyrics-in-closed"));

            var own = new Adw.ActionRow ();
            own.title = _("Your own lyrics");
            own.subtitle = _("Files named Artist - Title.lrc in %s take precedence.").printf (
                LyricsService.user_folder ().replace (Paths.home (), "~"));
            own.subtitle_lines = 0;
            var open = new Gtk.Button.with_label (_("Open the Folder"));
            open.valign = Gtk.Align.CENTER;
            open.clicked.connect (() => {
                DirUtils.create_with_parents (LyricsService.user_folder (), 0700);
                var launcher = new Gtk.FileLauncher (File.new_for_path (LyricsService.user_folder ()));
                launcher.launch.begin (get_root () as Gtk.Window, null);
            });
            own.add_suffix (open);
            group.add (own);

            var cache = new Adw.ActionRow ();
            cache.title = _("Lyrics kept on this computer");
            cache.subtitle = _("Forget them, so each song is asked again.");
            var clear = new Gtk.Button.with_label (_("Clear"));
            clear.valign = Gtk.Align.CENTER;
            clear.clicked.connect (() => {
                LyricsService.clear_cache ();
                clear.sensitive = false;
            });
            cache.add_suffix (clear);
            group.add (cache);
            page.add (group);
            return page;
        }

        Adw.PreferencesPage agents_page () {
            var page = new Adw.PreferencesPage ();
            page.title = _("Agents");
            page.icon_name = "utilities-terminal-symbolic";

            var group = new Adw.PreferencesGroup ();
            group.title = _("Coding agents");
            group.description = _("Sessions in the island, and permission requests with Allow and Deny. Col never signs in to any AI service: it only hears the hooks each agent calls on this computer. Connecting adds Col's hooks to the agent's settings and keeps a backup beside them.");
            foreach (var agent in HookAgent.all ()) {
                var row = new Adw.ActionRow ();
                row.title = agent.name ();
                var button = new Gtk.Button ();
                button.valign = Gtk.Align.CENTER;
                var current = agent;
                button.clicked.connect (() => toggle (current));
                row.add_suffix (button);
                group.add (row);
                agent_rows += row;
                agent_buttons += button;
            }
            page.add (group);
            refresh_agents ();

            var scripts = new Adw.PreferencesGroup ();
            scripts.title = _("Your scripts");
            scripts.description = _("Put your own live activities in the island from a terminal, a script or a hook.");
            string[] examples = {
                "colctl push build --title Build --symbol hammer --tint orange --progress 40%",
                "colctl done build",
                "colctl agent Aider working --message Refactoring",
            };
            foreach (var example in examples) {
                var row = new Adw.ActionRow ();
                row.title = example;
                row.title_selectable = true;
                row.add_css_class ("monospace");
                scripts.add (row);
            }
            var socket = new Adw.ActionRow ();
            socket.title = _("Local API");
            socket.subtitle = _("HTTP on the Unix socket %s, open to your account only.").printf (Paths.socket_path ());
            socket.subtitle_selectable = true;
            scripts.add (socket);
            page.add (scripts);
            return page;
        }

        void refresh_agents () {
            var agents = HookAgent.all ();
            for (int i = 0; i < agents.length && i < agent_rows.length; i++) {
                var agent = agents[i];
                bool connected = Hooks.is_connected (agent);
                agent_rows[i].subtitle = connected
                    ? (agent.agent == CodingAgent.CODEX ? _("Connected. In Codex, run /hooks once and trust Col's hooks.") : _("Connected"))
                    : (agent.is_present () ? _("Not connected") : _("Not found on this computer"));
                agent_buttons[i].label = connected ? _("Disconnect") : _("Connect");
                agent_buttons[i].sensitive = connected || agent.is_present ();
                if (connected) {
                    agent_buttons[i].remove_css_class ("suggested-action");
                } else {
                    agent_buttons[i].add_css_class ("suggested-action");
                }
            }
        }

        string? colctl_path () {
            var own = Paths.own_executable ();
            if (own != null) {
                var sibling = Path.build_filename (Path.get_dirname ((!) own), "colctl");
                if (FileUtils.test (sibling, FileTest.IS_EXECUTABLE)) {
                    return sibling;
                }
            }
            return Environment.find_program_in_path ("colctl");
        }

        void toggle (HookAgent agent) {
            bool connected = Hooks.is_connected (agent);
            try {
                Hooks.edit (agent, null, !connected, colctl_path ());
                add_toast (new Adw.Toast (connected ? _("Disconnected. %s no longer calls Col.").printf (agent.name ())
                    : _("Connected. New %s sessions report to Col.").printf (agent.name ())));
            } catch (HooksError e) {
                add_toast (new Adw.Toast (e.message));
            }
            refresh_agents ();
        }

        Adw.PreferencesPage about_page () {
            var page = new Adw.PreferencesPage ();
            page.title = _("About");
            page.icon_name = "help-about-symbolic";
            var group = new Adw.PreferencesGroup ();
            group.title = _("Col for Linux");
            group.description = _("A preview: the island, the music playing with its lyrics, your coding agents, the volume, the battery and a few tools. Col is free and open source, under the MIT license.");
            var about = new Adw.ActionRow ();
            about.title = _("About Col");
            about.activatable = true;
            about.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            about.activated.connect (() => show_about (this));
            group.add (about);
            var privacy = new Adw.ActionRow ();
            privacy.title = _("Privacy");
            privacy.subtitle = _("No account, no telemetry. Col reaches the network only for LRCLIB while lyrics are on, and for a cover when the player gives its address. Scripts and agents reach Col through a socket only your account can open.");
            privacy.subtitle_lines = 0;
            group.add (privacy);
            var quit = new Adw.ActionRow ();
            quit.title = _("Quit Col");
            quit.activatable = true;
            quit.activated.connect (() => {
                var app = GLib.Application.get_default ();
                if (app != null) {
                    app.quit ();
                }
            });
            group.add (quit);
            page.add (group);
            return page;
        }

        public static void show_about (Gtk.Widget? parent) {
            var about = new Adw.AboutDialog ();
            about.application_name = "Col";
            about.application_icon = Config.APP_ID;
            about.developer_name = "Ruben Catalao";
            about.version = _("%s (preview)").printf (Config.VERSION);
            about.comments = _("The island at the top of your screen: the song playing, its lyrics, your coding agents asking for permission, the volume and your own live activities.");
            about.website = "https://getcol.vercel.app";
            about.issue_url = "https://github.com/ruben4reall/col/issues";
            about.license_type = Gtk.License.MIT_X11;
            about.copyright = "© 2026 Ruben Catalao";
            about.present (parent);
        }
    }
}
