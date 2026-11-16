/* Everything the island shows, in one place: the song playing, its lyrics, the agents, the activities scripts pushed,
 * the timer, the battery, the volume. Monitors write here; the island and its pages read from here. */

namespace Col {
    /* What is playing. The position is extrapolated from the last one reported, as players report it only on seeks. */
    public class NowPlaying {
        public string title = "";
        public string artist = "";
        public string album = "";
        /* The player's own name: Spotify, Firefox, VLC... */
        public string player = "";
        public double duration = 0;
        /* Position at `timestamp`, in seconds; monotonic microseconds. */
        public double position = 0;
        public int64 timestamp = 0;
        public double rate = 1;
        public bool playing = false;
        public bool can_seek = true;
        public bool can_next = true;
        public bool can_previous = true;
        public Gdk.Texture? art;
        public string art_url = "";

        public string track_key () {
            return "%s\n%s\n%s".printf (title, artist, album);
        }

        public bool is_empty () {
            return title == "" && artist == "";
        }

        public double position_at (int64 now) {
            double moving = playing ? double.max (rate, 0) : 0;
            double result = position + (now - timestamp) / 1000000.0 * moving;
            return duration > 0 ? result.clamp (0, duration) : double.max (result, 0);
        }
    }

    public interface MediaControl : Object {
        public abstract void play_pause ();
        public abstract void next ();
        public abstract void previous ();
        public abstract void seek (double seconds);
    }

    /* A countdown. It ticks once a second while it runs, and never otherwise. */
    public class TimerTool : Object {
        /* When it ends, in monotonic microseconds; 0 when no timer runs. */
        public int64 ends = 0;
        public double total = 0;
        /* Screenshots: a timer that does not move. */
        public double frozen_remaining = -1;
        uint tick = 0;

        public signal void changed ();
        public signal void finished ();

        public bool running () {
            return ends > 0 || frozen_remaining >= 0;
        }

        public double remaining () {
            if (frozen_remaining >= 0) {
                return frozen_remaining;
            }
            if (ends == 0) {
                return 0;
            }
            return double.max (0, (ends - get_monotonic_time ()) / 1000000.0);
        }

        public void start (double seconds) {
            total = seconds;
            ends = get_monotonic_time () + (int64) (seconds * 1000000);
            schedule ();
            changed ();
        }

        public void add (double seconds) {
            if (ends == 0) {
                start (seconds);
                return;
            }
            ends += (int64) (seconds * 1000000);
            total += seconds;
            schedule ();
            changed ();
        }

        public void cancel () {
            ends = 0;
            frozen_remaining = -1;
            if (tick != 0) {
                Source.remove (tick);
                tick = 0;
            }
            changed ();
        }

        /* Wakes when the shown second changes. */
        void schedule () {
            if (tick != 0) {
                Source.remove (tick);
                tick = 0;
            }
            if (ends == 0) {
                return;
            }
            double left = remaining ();
            if (left <= 0) {
                ends = 0;
                finished ();
                changed ();
                return;
            }
            double fraction = left - Math.floor (left);
            uint wait = (uint) Math.ceil ((fraction > 0.001 ? fraction : 1.0) * 1000);
            tick = Timeout.add (wait, () => {
                tick = 0;
                schedule ();
                changed ();
                return Source.REMOVE;
            });
        }

        public static string format (double seconds) {
            int total = (int) Math.ceil (seconds);
            int hours = total / 3600, minutes = (total % 3600) / 60, rest = total % 60;
            if (hours > 0) {
                return "%d:%02d:%02d".printf (hours, minutes, rest);
            }
            return "%d:%02d".printf (minutes, rest);
        }
    }

    public class Model : Object {
        public Settings settings;
        public ActivityBoard board = new ActivityBoard ();
        public NowPlaying? media;
        public MediaControl? media_control;
        public Lyrics? lyrics;
        /* The track the lyrics belong to. */
        public string lyrics_track = "";
        public AgentCenter agents = new AgentCenter ();
        public CustomActivities custom = new CustomActivities ();
        public TimerTool timer = new TimerTool ();
        public ClipboardHistory clipboard;
        public bool awake = false;
        public bool battery_present = false;
        public double battery_level = 1;
        public bool battery_charging = false;
        /* Screenshots: nothing moves, nothing expires. */
        public bool frozen = false;

        public signal void changed ();
        public signal void media_changed ();
        public signal void lyrics_changed ();
        public signal void agents_changed ();
        public signal void battery_changed ();
        public signal void tools_changed ();
        public signal void open_requested (string page);
        public signal void awake_requested (bool on);
        public signal void settings_requested ();

        uint expiry_source = 0;
        uint lyric_source = 0;
        int64 paused_at = 0;

        public Model (Settings settings) {
            this.settings = settings;
            clipboard = new ClipboardHistory (settings);
            agents.changed.connect (() => {
                refresh_agents ();
                agents_changed ();
            });
            agents.requested.connect (() => open_requested ("live"));
            custom.changed.connect (() => {
                refresh_custom ();
                agents_changed ();
            });
            timer.changed.connect (() => {
                refresh_timer ();
                tools_changed ();
            });
            timer.finished.connect (on_timer_finished);
            clipboard.changed.connect (() => tools_changed ());
            settings.changed.connect ((key) => {
                if (key == "lyrics-in-closed" || key == "lyrics") {
                    refresh_media ();
                }
            });
        }

        public Activity? current () {
            return board.current (get_monotonic_time ());
        }

        /* Drops what expired, then wakes exactly when the next activity expires. */
        void publish () {
            int64 now = get_monotonic_time ();
            if (!frozen) {
                board.prune (now);
            }
            if (expiry_source != 0) {
                Source.remove (expiry_source);
                expiry_source = 0;
            }
            int64 next = frozen ? 0 : board.next_expiry (now);
            if (next > 0) {
                uint wait = (uint) ((next - now) / 1000 + 5);
                expiry_source = Timeout.add (wait, () => {
                    expiry_source = 0;
                    if (custom.prune (get_monotonic_time ())) {
                        agents_changed ();
                    }
                    publish ();
                    return Source.REMOVE;
                });
            }
            changed ();
        }

        /* ------------------------------------------------------------------------------------------------------- */
        /* Music */

        public void set_media (NowPlaying? next) {
            bool was_playing = media != null && media.playing;
            media = next;
            if (media != null && !media.playing && was_playing) {
                paused_at = get_monotonic_time ();
            }
            refresh_media ();
            media_changed ();
        }

        public void set_lyrics (Lyrics? lyrics, string track) {
            this.lyrics = lyrics;
            this.lyrics_track = track;
            refresh_media ();
            lyrics_changed ();
        }

        /* The lyrics of the song playing now, if they are its own. */
        public Lyrics? current_lyrics () {
            if (lyrics == null || media == null || lyrics_track != media.track_key () || !settings.lyrics) {
                return null;
            }
            return lyrics;
        }

        public void refresh_media () {
            if (lyric_source != 0) {
                Source.remove (lyric_source);
                lyric_source = 0;
            }
            if (media == null || media.is_empty ()) {
                board.remove ("media");
                publish ();
                return;
            }
            var activity = new Activity ("media", ActivityPriority.AMBIENT);
            activity.leading = CompactItem.art_item (media.art);
            activity.trailing = CompactItem.equalizer (media.playing);
            activity.middle = media.title != "" ? media.title : media.artist;
            var words = current_lyrics ();
            if (settings.lyrics_in_closed && words != null && words.is_synced && media.playing) {
                int64 now = get_monotonic_time ();
                double position = media.position_at (now);
                int index = words.index_at (position);
                if (index >= 0 && !words.lines[index].is_pause ()) {
                    activity.middle = words.lines[index].text;
                }
                double wait = words.wait_after (position, media.rate);
                if (wait > 0 && !frozen) {
                    lyric_source = Timeout.add ((uint) (wait * 1000), () => {
                        lyric_source = 0;
                        refresh_media ();
                        return Source.REMOVE;
                    });
                }
            }
            if (!media.playing) {
                // A paused song stays a moment, then leaves the closed island to whatever comes next.
                if (paused_at == 0) {
                    paused_at = get_monotonic_time ();
                }
                activity.expires = frozen ? 0 : paused_at + 10000000;
                if (activity.expires != 0 && activity.expires <= get_monotonic_time ()) {
                    board.remove ("media");
                    publish ();
                    return;
                }
            } else {
                paused_at = 0;
            }
            var previous = board.activities["media"];
            if (previous != null && previous.middle == activity.middle && media.playing) {
                activity.updated = previous.updated;
            }
            board.upsert (activity);
            publish ();
        }

        /* ------------------------------------------------------------------------------------------------------- */
        /* Agents and scripts */

        void refresh_agents () {
            int active;
            var top = agents.board.top (out active);
            if (top == null) {
                board.remove ("agents");
                publish ();
                return;
            }
            CodingAgent kind;
            if (!CodingAgent.from_name (top.agent, out kind)) {
                kind = CodingAgent.CLAUDE;
            }
            Activity activity;
            switch (top.state) {
            case SessionState.WAITING:
                activity = new Activity ("agents", ActivityPriority.ALERT);
                activity.leading = CompactItem.agent_item (kind, true);
                activity.trailing = CompactItem.glyph_item ("hand", Rgba.named_orange ());
                break;
            case SessionState.WORKING:
                activity = new Activity ("agents", ActivityPriority.STANDARD);
                activity.leading = CompactItem.agent_item (kind, false);
                activity.trailing = active > 1
                    ? CompactItem.text_item (active.to_string (), Rgba.named_white ())
                    : CompactItem.spinner ();
                break;
            default:
                activity = new Activity ("agents", ActivityPriority.TRANSIENT);
                activity.leading = CompactItem.agent_item (kind, false);
                activity.trailing = CompactItem.glyph_item ("check-circle", Rgba.named_green ());
                int64 age = get_real_time () - top.updated;
                activity.expires = get_monotonic_time () + int64.max (0, 4000000 - age);
                break;
            }
            activity.middle = top.project;
            board.upsert (activity);
            publish ();
        }

        void refresh_custom () {
            var keep = new GenericArray<string> ();
            foreach (var entry in custom.entries) {
                var request = entry.request;
                var tint = request.resolved_tint ();
                Activity activity;
                if (entry.finished) {
                    activity = new Activity ("api." + request.id, ActivityPriority.TRANSIENT);
                    activity.trailing = CompactItem.glyph_item ("check-circle", Rgba.named_green ());
                } else {
                    activity = new Activity ("api." + request.id, request.resolved_priority ());
                    if (request.has_progress) {
                        activity.trailing = CompactItem.ring (request.progress, tint);
                    } else if (request.text != null && request.text != "") {
                        activity.trailing = CompactItem.text_item ((!) request.text, tint);
                    }
                }
                activity.leading = CompactItem.glyph_item (Glyphs.resolve (request.symbol), tint);
                activity.middle = request.title;
                activity.expires = entry.expires;
                activity.updated = entry.updated;
                board.upsert (activity);
                keep.add (activity.id);
            }
            var gone = new GenericArray<string> ();
            board.activities.foreach ((id, activity) => {
                if (id.has_prefix ("api.")) {
                    bool kept = false;
                    foreach (var name in keep) {
                        if (name == id) {
                            kept = true;
                        }
                    }
                    if (!kept) {
                        gone.add (id);
                    }
                }
            });
            foreach (var id in gone) {
                board.remove (id);
            }
            publish ();
        }

        /* ------------------------------------------------------------------------------------------------------- */
        /* Tools */

        void refresh_timer () {
            if (!timer.running ()) {
                if (board.activities["timer"] != null && board.activities["timer"].priority != ActivityPriority.ALERT) {
                    board.remove ("timer");
                }
                publish ();
                return;
            }
            var activity = new Activity ("timer", ActivityPriority.STANDARD);
            activity.leading = CompactItem.glyph_item ("timer", Rgba.named_orange ());
            activity.trailing = CompactItem.text_item (TimerTool.format (timer.remaining ()), Rgba.named_orange ());
            var previous = board.activities["timer"];
            if (previous != null) {
                activity.updated = previous.updated;
            }
            board.upsert (activity);
            publish ();
        }

        void on_timer_finished () {
            var activity = new Activity ("timer", ActivityPriority.ALERT);
            activity.leading = CompactItem.glyph_item ("timer", Rgba.named_orange ());
            activity.middle = _("Time is up");
            activity.middle_tint = Rgba.named_orange ();
            activity.trailing = CompactItem.glyph_item ("check-circle", Rgba.named_orange ());
            activity.expires = get_monotonic_time () + 8000000;
            board.upsert (activity);
            publish ();
            var display = Gdk.Display.get_default ();
            if (display != null) {
                display.beep ();
            }
        }

        public void set_awake (bool on) {
            awake = on;
            if (on) {
                var activity = new Activity ("awake", ActivityPriority.AMBIENT);
                activity.leading = CompactItem.glyph_item ("cup", Rgba.named_white ());
                activity.middle = _("Awake");
                activity.middle_tint = Rgba (1, 1, 1, 0.7);
                board.upsert (activity);
            } else {
                board.remove ("awake");
            }
            publish ();
            tools_changed ();
        }

        /* ------------------------------------------------------------------------------------------------------- */
        /* System */

        public void show_volume (double volume, bool muted) {
            if (!settings.volume_display) {
                return;
            }
            var activity = new Activity ("volume", ActivityPriority.TRANSIENT);
            activity.leading = CompactItem.glyph_item (muted || volume <= 0.001 ? "speaker-muted" : "speaker", Rgba.named_white ());
            activity.trailing = CompactItem.level (volume, muted);
            activity.middle = muted ? _("Muted") : "%d%%".printf ((int) Math.round (volume * 100));
            activity.middle_tint = Rgba (1, 1, 1, 0.7);
            activity.expires = frozen ? 0 : get_monotonic_time () + 1600000;
            board.upsert (activity);
            publish ();
        }

        public void set_battery (bool present, double level, bool charging) {
            bool was_charging = battery_charging, was_present = battery_present;
            double was_level = battery_level;
            battery_present = present;
            battery_level = level;
            battery_charging = charging;
            battery_changed ();
            if (!present || !settings.battery_display || !was_present) {
                return;
            }
            if (charging && !was_charging) {
                var activity = new Activity ("power", ActivityPriority.TRANSIENT);
                activity.leading = CompactItem.glyph_item ("bolt", Rgba.named_green ());
                activity.middle = _("Charging, %d%%").printf ((int) Math.round (level * 100));
                activity.trailing = CompactItem.battery (level, true);
                activity.expires = frozen ? 0 : get_monotonic_time () + 3000000;
                board.upsert (activity);
                publish ();
            } else if (!charging && (level <= 0.2 && was_level > 0.2 || level <= 0.1 && was_level > 0.1)) {
                var activity = new Activity ("battery", ActivityPriority.ALERT);
                activity.leading = CompactItem.glyph_item ("alert", Rgba.named_red ());
                activity.middle = _("Low battery, %d%%").printf ((int) Math.round (level * 100));
                activity.middle_tint = Rgba.named_red ();
                activity.trailing = CompactItem.battery (level, false);
                activity.expires = frozen ? 0 : get_monotonic_time () + 6000000;
                board.upsert (activity);
                publish ();
            }
        }

        /* Puts an activity on the board as it is, for screenshots. */
        public void post (Activity activity) {
            board.upsert (activity);
            publish ();
        }
    }
}
