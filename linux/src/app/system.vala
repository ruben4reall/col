/* The system around the island: the clipboard, keeping the screen awake, the battery and the volume. Each follows the
 * system's own events; none polls. */

namespace Col {
    /* What the user copied, in memory only. The copies they pin are kept in the settings; copies that password
     * managers mark as secret never enter. */
    public class ClipboardHistory : Object {
        public GenericArray<string> items = new GenericArray<string> ();
        public const int LIMIT = 30;
        Settings settings;
        Platform.DataControl? control;
        Gdk.Clipboard? gdk_clipboard;
        ulong gdk_handler = 0;
        string? own;

        public signal void changed ();

        public ClipboardHistory (Settings settings) {
            this.settings = settings;
        }

        public void start (Gdk.Display display) {
            if (!settings.clipboard_history || control != null || gdk_clipboard != null) {
                return;
            }
            control = Platform.DataControl.create (display, on_text);
            if (control == null && Platform.is_x11 (display)) {
                // X11 reports every change of the clipboard to any window.
                gdk_clipboard = display.get_clipboard ();
                gdk_handler = gdk_clipboard.changed.connect (() => {
                    if (gdk_clipboard.get_formats ().contain_mime_type ("x-kde-passwordManagerHint")) {
                        return;
                    }
                    gdk_clipboard.read_text_async.begin (null, (obj, result) => {
                        try {
                            var text = gdk_clipboard.read_text_async.end (result);
                            if (text != null) {
                                add ((!) text);
                            }
                        } catch (Error e) {
                        }
                    });
                });
            }
        }

        public void stop () {
            control = null;
            if (gdk_clipboard != null && gdk_handler != 0) {
                gdk_clipboard.disconnect (gdk_handler);
            }
            gdk_clipboard = null;
            gdk_handler = 0;
            items = new GenericArray<string> ();
            changed ();
        }

        public bool available () {
            return control != null || gdk_clipboard != null;
        }

        void on_text (string? text, bool secret) {
            if (secret || text == null) {
                return;
            }
            add ((!) text);
        }

        public void add (string text) {
            if (text.strip () == "") {
                return;
            }
            for (int i = 0; i < items.length; i++) {
                if (items[i] == text) {
                    items.remove_index (i);
                    break;
                }
            }
            items.insert (0, text);
            while (items.length > LIMIT) {
                items.remove_index (items.length - 1);
            }
            changed ();
        }

        /* Puts a copy back on the clipboard. */
        public void copy (string text) {
            own = text;
            if (control != null) {
                control.set_text (text);
            } else {
                var display = Gdk.Display.get_default ();
                if (display != null) {
                    display.get_clipboard ().set_text (text);
                }
            }
            add (text);
        }

        public bool is_pinned (string text) {
            foreach (var pin in settings.pins) {
                if (pin == text) {
                    return true;
                }
            }
            return false;
        }

        public void toggle_pin (string text) {
            var pins = new GenericArray<string> ();
            bool found = false;
            foreach (var pin in settings.pins) {
                if (pin == text) {
                    found = true;
                } else {
                    pins.add (pin);
                }
            }
            if (!found) {
                pins.insert (0, text);
            }
            settings.set_pins (pins);
            changed ();
        }

        /* Pins first, then the history, each copy once. */
        public GenericArray<string> shown () {
            var list = new GenericArray<string> ();
            foreach (var pin in settings.pins) {
                list.add (pin);
            }
            foreach (var item in items) {
                if (!is_pinned (item)) {
                    list.add (item);
                }
            }
            return list;
        }
    }

    /* Keeps the screen and the computer awake: the Wayland idle inhibitor on the island's own surface where the
     * compositor has one, the desktop's session manager otherwise, and logind so the computer does not sleep. */
    public class KeepAwake : Object {
        Gtk.Application app;
        Gtk.Window window;
        bool surface_inhibited = false;
        uint app_cookie = 0;
        int sleep_fd = -1;
        public bool active { get; private set; default = false; }

        public KeepAwake (Gtk.Application app, Gtk.Window window) {
            this.app = app;
            this.window = window;
        }

        public void switch_to (bool on) {
            if (on == active) {
                return;
            }
            active = on;
            if (on) {
                surface_inhibited = Platform.idle_inhibit (window, true);
                if (!surface_inhibited) {
                    app_cookie = app.inhibit (window, Gtk.ApplicationInhibitFlags.IDLE | Gtk.ApplicationInhibitFlags.SUSPEND,
                                              _("Keep awake is on in Col"));
                }
                inhibit_sleep.begin ();
            } else {
                if (surface_inhibited) {
                    Platform.idle_inhibit (window, false);
                    surface_inhibited = false;
                }
                if (app_cookie != 0) {
                    app.uninhibit (app_cookie);
                    app_cookie = 0;
                }
                if (sleep_fd >= 0) {
                    Posix.close (sleep_fd);
                    sleep_fd = -1;
                }
            }
        }

        /* The surface was made again (another monitor): its inhibitor goes with it. */
        public void surface_changed () {
            if (active && surface_inhibited) {
                Platform.idle_inhibit (window, true);
            }
        }

        async void inhibit_sleep () {
            try {
                var bus = yield Bus.get (BusType.SYSTEM);
                UnixFDList fds;
                var reply = yield bus.call_with_unix_fd_list ("org.freedesktop.login1", "/org/freedesktop/login1",
                    "org.freedesktop.login1.Manager", "Inhibit",
                    new Variant ("(ssss)", "sleep:idle", "Col", _("Keep awake is on in Col"), "block"),
                    new VariantType ("(h)"), DBusCallFlags.NONE, 2000, null, null, out fds);
                int32 handle;
                reply.get ("(h)", out handle);
                int fd = fds.get (handle);
                if (!active) {
                    Posix.close (fd);
                    return;
                }
                sleep_fd = fd;
            } catch (Error e) {
                debug ("logind inhibitor: %s", e.message);
            }
        }
    }

    /* The battery, from UPower's display device: the one the desktop shows. */
    public class BatteryMonitor : Object {
        DBusProxy? proxy;
        Model model;

        public BatteryMonitor (Model model) {
            this.model = model;
        }

        public async void start () {
            try {
                proxy = yield new DBusProxy.for_bus (BusType.SYSTEM, DBusProxyFlags.NONE, null, "org.freedesktop.UPower",
                    "/org/freedesktop/UPower/devices/DisplayDevice", "org.freedesktop.UPower.Device", null);
                proxy.g_properties_changed.connect (() => read ());
                read ();
            } catch (Error e) {
                debug ("UPower: %s", e.message);
            }
        }

        void read () {
            var present = proxy.get_cached_property ("IsPresent");
            var type = proxy.get_cached_property ("Type");
            var percentage = proxy.get_cached_property ("Percentage");
            var state = proxy.get_cached_property ("State");
            if (present == null || percentage == null || state == null) {
                return;
            }
            // Type 2 is a battery; a desktop's display device is a line power or nothing.
            bool is_battery = present.get_boolean () && (type == null || type.get_uint32 () == 2);
            uint32 value = state.get_uint32 ();
            // 1 charging, 4 fully charged, 5 pending charge: the charger is in.
            bool charging = value == 1 || value == 4 || value == 5;
            model.set_battery (is_battery, percentage.get_double () / 100, charging);
        }
    }

    /* The volume of the default output, from PulseAudio or PipeWire's PulseAudio server: an event on each change. */
    public class VolumeMonitor : Object {
        PulseAudio.GLibMainLoop loop;
        PulseAudio.Context? context;
        Model model;
        string default_sink = "";
        uint32 sink_index = uint32.MAX;
        double volume = -1;
        bool muted = false;
        int retries = 0;

        public VolumeMonitor (Model model) {
            this.model = model;
            loop = new PulseAudio.GLibMainLoop ();
        }

        public void start () {
            context = new PulseAudio.Context (loop.get_api (), "Col");
            context.set_state_callback (on_state);
            if (context.connect (null, PulseAudio.Context.Flags.NOAUTOSPAWN, null) < 0) {
                context = null;
            }
        }

        void on_state (PulseAudio.Context c) {
            switch (c.get_state ()) {
            case PulseAudio.Context.State.READY:
                retries = 0;
                c.set_subscribe_callback (on_event);
                c.subscribe (PulseAudio.Context.SubscriptionMask.SINK | PulseAudio.Context.SubscriptionMask.SERVER);
                c.get_server_info (on_server);
                break;
            case PulseAudio.Context.State.FAILED:
            case PulseAudio.Context.State.TERMINATED:
                // The sound server restarted: try again a few times, then stay quiet.
                if (retries < 5) {
                    retries++;
                    Timeout.add_seconds (2 * retries, () => {
                        start ();
                        return Source.REMOVE;
                    });
                }
                break;
            default:
                break;
            }
        }

        void on_server (PulseAudio.Context c, PulseAudio.ServerInfo? info) {
            if (info == null || info.default_sink_name == null) {
                return;
            }
            default_sink = info.default_sink_name;
            c.get_sink_info_by_name (default_sink, on_sink);
        }

        void on_event (PulseAudio.Context c, PulseAudio.Context.SubscriptionEventType type, uint32 index) {
            var facility = type & PulseAudio.Context.SubscriptionEventType.FACILITY_MASK;
            if (facility == PulseAudio.Context.SubscriptionEventType.SERVER) {
                c.get_server_info (on_server);
            } else if (facility == PulseAudio.Context.SubscriptionEventType.SINK && index == sink_index) {
                c.get_sink_info_by_index (index, on_sink);
            }
        }

        void on_sink (PulseAudio.Context c, PulseAudio.SinkInfo? info, int eol) {
            if (info == null || eol != 0) {
                return;
            }
            bool same_sink = info.index == sink_index;
            sink_index = info.index;
            double level = (double) info.volume.avg () / (double) PulseAudio.Volume.NORM;
            bool mute = info.mute != 0;
            // Only a change of the same output is shown: never the first reading, nor a switch of output.
            if (same_sink && volume >= 0 && (Math.fabs (level - volume) > 0.004 || mute != muted)) {
                model.show_volume (level.clamp (0, 1), mute);
            }
            volume = level;
            muted = mute;
        }
    }
}
