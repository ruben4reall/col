/* Col's settings, in $XDG_CONFIG_HOME/col/settings.json: plain JSON, so it can be read, backed up and synced. Every
 * change is written at once and announced with `changed`. */

namespace Col {
    public class Settings : Object {
        public signal void changed (string key);

        /* Show the capsule at rest, or only when something happens (the default). */
        public bool visible_at_rest { get; set; default = false; }
        public bool open_on_hover { get; set; default = true; }
        public string size { get; set; default = "standard"; }
        /* A monitor's connector (DP-1, eDP-1...), or "" to let the compositor choose. */
        public string monitor { get; set; default = ""; }
        /* Below any panel at the top of the screen instead of over it. */
        public bool below_panels { get; set; default = false; }
        public bool lyrics { get; set; default = true; }
        public bool lyrics_in_closed { get; set; default = false; }
        public bool volume_display { get; set; default = true; }
        public bool battery_display { get; set; default = true; }
        public bool clipboard_history { get; set; default = true; }
        public bool welcome_shown { get; set; default = false; }
        /* Col opens with its intro: light around the pill, waves, the island swelling, and a chime. */
        public bool intro { get; set; default = true; }
        public bool intro_sound { get; set; default = true; }

        /* The copies the user pinned: the only ones of the clipboard history that are saved. */
        public GenericArray<string> pins = new GenericArray<string> ();

        string path;
        bool loading = false;

        public Settings (string? path = null) {
            this.path = path ?? Path.build_filename (Paths.config_dir (), "settings.json");
            load ();
            notify.connect ((spec) => {
                if (!loading) {
                    save ();
                    changed (spec.name);
                }
            });
        }

        public IslandSize island_size () {
            return IslandSize.from_key (size);
        }

        void load () {
            string text;
            try {
                if (!FileUtils.get_contents (path, out text)) {
                    return;
                }
            } catch (FileError e) {
                return;
            }
            var object = JsonText.parse_object (text);
            if (object == null) {
                return;
            }
            loading = true;
            visible_at_rest = JsonText.get_bool (object, "visible-at-rest", visible_at_rest);
            open_on_hover = JsonText.get_bool (object, "open-on-hover", open_on_hover);
            size = JsonText.get_string (object, "size") ?? size;
            monitor = JsonText.get_string (object, "monitor") ?? monitor;
            below_panels = JsonText.get_bool (object, "below-panels", below_panels);
            lyrics = JsonText.get_bool (object, "lyrics", lyrics);
            lyrics_in_closed = JsonText.get_bool (object, "lyrics-in-closed", lyrics_in_closed);
            volume_display = JsonText.get_bool (object, "volume-display", volume_display);
            battery_display = JsonText.get_bool (object, "battery-display", battery_display);
            clipboard_history = JsonText.get_bool (object, "clipboard-history", clipboard_history);
            welcome_shown = JsonText.get_bool (object, "welcome-shown", welcome_shown);
            intro = JsonText.get_bool (object, "intro", intro);
            intro_sound = JsonText.get_bool (object, "intro-sound", intro_sound);
            var saved = JsonText.get_array (object, "pins");
            if (saved != null) {
                for (uint i = 0; i < saved.get_length (); i++) {
                    var node = saved.get_element (i);
                    if (node.get_node_type () == Json.NodeType.VALUE && node.get_value_type () == typeof (string)) {
                        pins.add (node.get_string ());
                    }
                }
            }
            loading = false;
        }

        public void save () {
            var object = new Json.Object ();
            object.set_boolean_member ("visible-at-rest", visible_at_rest);
            object.set_boolean_member ("open-on-hover", open_on_hover);
            object.set_string_member ("size", size);
            object.set_string_member ("monitor", monitor);
            object.set_boolean_member ("below-panels", below_panels);
            object.set_boolean_member ("lyrics", lyrics);
            object.set_boolean_member ("lyrics-in-closed", lyrics_in_closed);
            object.set_boolean_member ("volume-display", volume_display);
            object.set_boolean_member ("battery-display", battery_display);
            object.set_boolean_member ("clipboard-history", clipboard_history);
            object.set_boolean_member ("welcome-shown", welcome_shown);
            object.set_boolean_member ("intro", intro);
            object.set_boolean_member ("intro-sound", intro_sound);
            var array = new Json.Array ();
            foreach (var pin in pins) {
                array.add_string_element (pin);
            }
            object.set_array_member ("pins", array);
            var root = new Json.Node (Json.NodeType.OBJECT);
            root.set_object (object);
            DirUtils.create_with_parents (Path.get_dirname (path), 0700);
            // Pinned copies can be private: the file is the user's alone.
            Hooks.write_whole (path, JsonText.pretty (root), 0600);
        }

        public void set_pins (GenericArray<string> list) {
            pins = list;
            save ();
            changed ("pins");
        }

        /* Opening at login: a desktop entry in ~/.config/autostart, as the XDG autostart specification says. */
        public static string autostart_path () {
            return Path.build_filename (Environment.get_user_config_dir (), "autostart", Config.APP_ID + ".desktop");
        }

        public static bool autostart_enabled () {
            return FileUtils.test (autostart_path (), FileTest.EXISTS);
        }

        public static void set_autostart (bool enabled) {
            var file = autostart_path ();
            if (!enabled) {
                FileUtils.unlink (file);
                return;
            }
            var program = Paths.own_executable () ?? "col";
            var entry = string.join ("\n",
                "[Desktop Entry]",
                "Type=Application",
                "Name=Col",
                "Comment=" + _("The island at the top of your screen"),
                "Exec=%s --autostart".printf (program.replace (" ", "\\s")),
                "Icon=" + Config.APP_ID,
                "Terminal=false",
                "NoDisplay=true",
                "X-GNOME-Autostart-enabled=true",
                "");
            DirUtils.create_with_parents (Path.get_dirname (file), 0700);
            try {
                FileUtils.set_contents (file, entry);
            } catch (FileError e) {
                warning ("autostart: %s", e.message);
            }
        }
    }
}
