/* The app: one island per session, the monitors that feed it, the local API, and the settings window. A second `col`
 * hands its command line to the one already running, as GApplication does: `col --settings`, `col col://push?...`. */

namespace Col {
    public class App : Adw.Application {
        public Settings settings;
        public Model model;
        public IslandWindow? island;
        string? demo;
        ControlServer? server;
        MprisWatcher? mpris;
        LyricsFollower? lyrics;
        VolumeMonitor? volume;
        BatteryMonitor? battery;
        KeepAwake? awake;
        Adw.Dialog? preferences;
        bool started = false;

        public App (string? demo) {
            Object (application_id: Config.APP_ID,
                    flags: ApplicationFlags.HANDLES_COMMAND_LINE | (demo != null ? ApplicationFlags.NON_UNIQUE : 0));
            this.demo = demo;
        }

        public override void startup () {
            base.startup ();
            Style.load ((!) Gdk.Display.get_default ());
            if (demo != null) {
                // Screenshots never read or change the user's settings.
                var path = Path.build_filename (Environment.get_tmp_dir (), "col-demo-%d.json".printf ((int) Posix.getpid ()));
                FileUtils.unlink (path);
                settings = new Settings (path);
            } else {
                settings = new Settings ();
            }
            model = new Model (settings);
            island = new IslandWindow (this, model);
            island.view.settings_requested.connect (show_settings);
            model.settings_requested.connect (show_settings);

            var settings_action = new SimpleAction ("settings", null);
            settings_action.activate.connect (() => show_settings ());
            add_action (settings_action);
            var about_action = new SimpleAction ("about", null);
            about_action.activate.connect (() => Preferences.show_about (null));
            add_action (about_action);
            var quit_action = new SimpleAction ("quit", null);
            quit_action.activate.connect (() => quit ());
            add_action (quit_action);
        }

        void start_services () {
            if (started) {
                return;
            }
            started = true;
            if (demo != null) {
                Demo.apply (model, island.view, (!) demo);
                return;
            }
            server = new ControlServer (model);
            try {
                server.start ();
            } catch (Error e) {
                warning ("the local API is off: %s", e.message);
                server = null;
            }
            var art = new ArtLoader ();
            mpris = new MprisWatcher (model, art);
            model.media_control = mpris;
            mpris.start.begin ();
            lyrics = new LyricsFollower (model);
            volume = new VolumeMonitor (model);
            volume.start ();
            battery = new BatteryMonitor (model);
            battery.start.begin ();
            model.clipboard.start (island.get_display ());
            awake = new KeepAwake (this, island);
            model.awake_requested.connect ((on) => {
                awake.switch_to (on);
                model.set_awake (awake.active);
            });
            settings.changed.connect ((key) => {
                if (key == "clipboard-history") {
                    if (settings.clipboard_history) {
                        model.clipboard.start (island.get_display ());
                    } else {
                        model.clipboard.stop ();
                    }
                    model.tools_changed ();
                }
            });
            if (!settings.welcome_shown) {
                settings.welcome_shown = true;
                show_settings_with (true);
            }
        }

        public override void shutdown () {
            if (server != null) {
                server.stop ();
            }
            if (awake != null) {
                awake.switch_to (false);
            }
            base.shutdown ();
        }

        public override void activate () {
            island.present ();
            start_services ();
        }

        public override int command_line (ApplicationCommandLine command) {
            var args = command.get_arguments ();
            // Col opened again from the applications menu, while it runs: its settings, the only window it has.
            bool wants_settings = started && args.length <= 1;
            for (int i = 1; i < args.length; i++) {
                var arg = args[i];
                if (arg == "--settings") {
                    wants_settings = true;
                } else if (arg == "--quit") {
                    quit ();
                    return 0;
                } else if (arg == "--demo") {
                    i++;
                } else if (arg.has_prefix ("col://") || arg.has_prefix ("islet://")) {
                    ControlServer.open_link (model, arg);
                }
            }
            activate ();
            if (wants_settings) {
                show_settings ();
            }
            return 0;
        }

        public void show_settings () {
            show_settings_with (false);
        }

        void show_settings_with (bool welcome) {
            if (preferences != null) {
                preferences.present (null);
                return;
            }
            var dialog = new Preferences (settings, welcome);
            dialog.closed.connect (() => preferences = null);
            preferences = dialog;
            dialog.present (null);
        }
    }
}
