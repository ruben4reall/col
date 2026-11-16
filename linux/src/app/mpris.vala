/* Now playing, from MPRIS: every player on the session bus that implements org.mpris.MediaPlayer2 (Spotify, browsers,
 * VLC, mpv with its plugin, Rhythmbox...). Written from the MPRIS specification. Players report their position only
 * when asked and on seeks, and some always say 0: the position is the last one known plus the time played since. */

namespace Col {
    class MprisPlayer : Object {
        public string bus_name;
        public DBusProxy? proxy;
        public string identity = "";
        public string status = "Stopped";
        public string title = "";
        public string artist = "";
        public string album = "";
        public string art_url = "";
        public string track_id = "";
        /* Microseconds. */
        public int64 length = 0;
        public double rate = 1;
        public bool can_seek = false;
        public bool can_next = false;
        public bool can_previous = false;
        public int64 base_position = 0;
        public int64 base_time = 0;
        /* The player answers 0 whatever the position: only its seeks and our own estimate count. */
        public bool reports_zero = false;
        /* When it last started playing, to pick the player the user is listening to. */
        public int64 active_since = 0;
        public int64 seen = 0;

        public signal void changed ();
        public signal void gone ();

        public MprisPlayer (string bus_name) {
            this.bus_name = bus_name;
        }

        public bool playing () {
            return status == "Playing";
        }

        public bool has_track () {
            return title != "" || artist != "";
        }

        public string track_key () {
            return "%s\n%s\n%s\n%s".printf (title, artist, album, track_id);
        }

        public int64 position_now () {
            int64 elapsed = playing () ? (int64) ((get_monotonic_time () - base_time) * double.max (rate, 0)) : 0;
            int64 position = base_position + elapsed;
            if (length > 0) {
                position = int64.min (position, length);
            }
            return int64.max (0, position);
        }

        public async void start (DBusConnection bus) {
            try {
                proxy = yield new DBusProxy (bus, DBusProxyFlags.GET_INVALIDATED_PROPERTIES, null, bus_name,
                    "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", null);
            } catch (Error e) {
                return;
            }
            proxy.g_properties_changed.connect ((changed, invalidated) => read (false));
            proxy.g_signal.connect ((sender, name, parameters) => {
                if (name == "Seeked" && parameters.n_children () == 1) {
                    base_position = number (parameters.get_child_value (0));
                    base_time = get_monotonic_time ();
                    changed ();
                }
            });
            try {
                var reply = yield bus.call (bus_name, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties", "Get",
                    new Variant ("(ss)", "org.mpris.MediaPlayer2", "Identity"), new VariantType ("(v)"),
                    DBusCallFlags.NONE, 1000, null);
                var value = reply.get_child_value (0).get_variant ();
                if (value.is_of_type (VariantType.STRING)) {
                    identity = value.get_string ();
                }
            } catch (Error e) {
            }
            read (true);
        }

        /* Any number a player might send for a time. */
        static int64 number (Variant value) {
            var v = value.is_of_type (VariantType.VARIANT) ? value.get_variant () : value;
            if (v.is_of_type (VariantType.INT64)) return v.get_int64 ();
            if (v.is_of_type (VariantType.UINT64)) return (int64) v.get_uint64 ();
            if (v.is_of_type (VariantType.INT32)) return v.get_int32 ();
            if (v.is_of_type (VariantType.UINT32)) return v.get_uint32 ();
            if (v.is_of_type (VariantType.DOUBLE)) return (int64) v.get_double ();
            return 0;
        }

        static string text (Variant? value) {
            if (value == null) {
                return "";
            }
            if (value.is_of_type (VariantType.STRING) || value.is_of_type (VariantType.OBJECT_PATH)) {
                return value.get_string ();
            }
            if (value.is_of_type (VariantType.STRING_ARRAY)) {
                var list = value.get_strv ();
                return string.joinv (", ", list);
            }
            return "";
        }

        bool flag (string name, bool fallback) {
            var value = proxy.get_cached_property (name);
            return value != null && value.is_of_type (VariantType.BOOLEAN) ? value.get_boolean () : fallback;
        }

        void read (bool initial) {
            var previous_key = track_key ();
            bool was_playing = playing ();
            int64 now = get_monotonic_time ();
            int64 position = position_now ();

            var status_value = proxy.get_cached_property ("PlaybackStatus");
            status = status_value != null && status_value.is_of_type (VariantType.STRING) ? status_value.get_string () : "Stopped";
            var rate_value = proxy.get_cached_property ("Rate");
            double next_rate = rate_value != null && rate_value.is_of_type (VariantType.DOUBLE) ? rate_value.get_double () : 1;
            can_seek = flag ("CanSeek", false);
            can_next = flag ("CanGoNext", true);
            can_previous = flag ("CanGoPrevious", true);

            var metadata = proxy.get_cached_property ("Metadata");
            if (metadata != null && metadata.is_of_type (new VariantType ("a{sv}"))) {
                title = text (metadata.lookup_value ("xesam:title", null));
                artist = text (metadata.lookup_value ("xesam:artist", null));
                album = text (metadata.lookup_value ("xesam:album", null));
                art_url = text (metadata.lookup_value ("mpris:artUrl", null));
                track_id = text (metadata.lookup_value ("mpris:trackid", null));
                var length_value = metadata.lookup_value ("mpris:length", null);
                length = length_value != null ? number (length_value) : 0;
            }

            if (track_key () != previous_key && !initial) {
                // A new track starts at its beginning, until the player says otherwise.
                base_position = 0;
                base_time = now;
            } else if (was_playing != playing () || next_rate != rate) {
                // Paused, resumed, or faster: the position so far is kept, and counts from now.
                base_position = position;
                base_time = now;
            }
            rate = next_rate;
            if (playing () && (!was_playing || initial)) {
                active_since = now;
            }
            seen = now;
            changed ();
            refresh_position.begin ();
        }

        public async void refresh_position () {
            if (proxy == null) {
                return;
            }
            try {
                var reply = yield proxy.get_connection ().call (bus_name, "/org/mpris/MediaPlayer2",
                    "org.freedesktop.DBus.Properties", "Get",
                    new Variant ("(ss)", "org.mpris.MediaPlayer2.Player", "Position"), new VariantType ("(v)"),
                    DBusCallFlags.NONE, 1000, null);
                int64 reported = number (reply.get_child_value (0));
                int64 estimate = position_now ();
                if (reported == 0 && estimate > 1500000) {
                    reports_zero = true;
                    return;
                }
                base_position = reported;
                base_time = get_monotonic_time ();
                changed ();
            } catch (Error e) {
            }
        }

        public void call (string method, Variant? parameters = null) {
            if (proxy == null) {
                return;
            }
            proxy.call.begin (method, parameters, DBusCallFlags.NONE, 2000, null, (obj, result) => {
                try {
                    proxy.call.end (result);
                } catch (Error e) {
                    debug ("%s %s: %s", bus_name, method, e.message);
                }
            });
        }
    }

    public class MprisWatcher : Object, MediaControl {
        const string PREFIX = "org.mpris.MediaPlayer2.";

        Model model;
        ArtLoader art;
        DBusConnection? bus;
        HashTable<string, MprisPlayer> players = new HashTable<string, MprisPlayer> (str_hash, str_equal);
        MprisPlayer? active;
        string loading_art = "";

        public MprisWatcher (Model model, ArtLoader art) {
            this.model = model;
            this.art = art;
        }

        public async void start () {
            try {
                bus = yield Bus.get (BusType.SESSION);
            } catch (Error e) {
                warning ("session bus: %s", e.message);
                return;
            }
            bus.signal_subscribe ("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged", "/org/freedesktop/DBus",
                "org.mpris.MediaPlayer2", DBusSignalFlags.MATCH_ARG0_NAMESPACE, (connection, sender, path, iface, signal_name, parameters) => {
                    string name, old_owner, new_owner;
                    parameters.get ("(sss)", out name, out old_owner, out new_owner);
                    if (old_owner != "") {
                        remove (name);
                    }
                    if (new_owner != "") {
                        add (name);
                    }
                });
            try {
                var reply = yield bus.call ("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                    "ListNames", null, new VariantType ("(as)"), DBusCallFlags.NONE, 2000, null);
                foreach (var name in reply.get_child_value (0).get_strv ()) {
                    add (name);
                }
            } catch (Error e) {
                warning ("ListNames: %s", e.message);
            }
        }

        void add (string name) {
            // playerctld mirrors another player: it would show every song twice.
            if (!name.has_prefix (PREFIX) || name.has_prefix (PREFIX + "playerctld") || players.contains (name)) {
                return;
            }
            var player = new MprisPlayer (name);
            players[name] = player;
            player.changed.connect (() => pick ());
            player.start.begin (bus);
        }

        void remove (string name) {
            if (players.remove (name)) {
                pick ();
            }
        }

        /* The player the user listens to: the one that started playing last; else the one shown, while it is there;
         * else any that has a track. */
        void pick () {
            MprisPlayer? best = null;
            players.foreach ((name, player) => {
                if (player.playing () && player.has_track () && (best == null || player.active_since > best.active_since)) {
                    best = player;
                }
            });
            if (best == null && active != null && players.contains (active.bus_name) && active.has_track ()) {
                best = active;
            }
            if (best == null) {
                players.foreach ((name, player) => {
                    if (player.has_track () && (best == null || player.seen > best.seen)) {
                        best = player;
                    }
                });
            }
            active = best;
            publish ();
        }

        void publish () {
            if (active == null) {
                model.set_media (null);
                return;
            }
            var player = (!) active;
            var media = new NowPlaying ();
            media.title = player.title;
            media.artist = player.artist;
            media.album = player.album;
            media.player = player.identity;
            media.duration = player.length / 1000000.0;
            media.position = player.position_now () / 1000000.0;
            media.timestamp = get_monotonic_time ();
            media.rate = player.rate;
            media.playing = player.playing ();
            media.can_seek = player.can_seek;
            media.can_next = player.can_next;
            media.can_previous = player.can_previous;
            media.art_url = player.art_url;
            media.art = art.cached (player.art_url);
            if (media.art == null && player.art_url != "" && loading_art != player.art_url) {
                var url = player.art_url;
                loading_art = url;
                art.load.begin (url, (obj, result) => {
                    art.load.end (result);
                    loading_art = "";
                    if (active != null && active.art_url == url) {
                        publish ();
                    }
                });
            }
            model.set_media (media);
        }

        public void play_pause () {
            if (active != null) {
                active.call ("PlayPause");
            }
        }

        public void next () {
            if (active != null) {
                active.call ("Next");
            }
        }

        public void previous () {
            if (active != null) {
                active.call ("Previous");
            }
        }

        public void seek (double seconds) {
            if (active == null) {
                return;
            }
            var player = (!) active;
            int64 target = (int64) (seconds * 1000000);
            if (player.track_id != "" && Variant.is_object_path (player.track_id)) {
                player.call ("SetPosition", new Variant ("(ox)", player.track_id, target));
            } else {
                player.call ("Seek", new Variant ("(x)", target - player.position_now ()));
            }
            // Shown at once; the player's Seeked signal confirms it.
            player.base_position = target;
            player.base_time = get_monotonic_time ();
            publish ();
        }
    }
}
