/* What the closed island shows: live activities, and the rule that picks the one that wins. */

namespace Col {
    public enum ItemKind {
        GLYPH,
        ART,
        EQUALIZER,
        TEXT,
        RING,
        LEVEL,
        BATTERY,
        SPINNER,
        AGENT
    }

    /* One side of the closed island. */
    public class CompactItem {
        public ItemKind kind;
        public string glyph = "";
        public Rgba tint = Rgba.named_white ();
        public double value = 0;
        public bool flag = false;
        public string text = "";
        public Gdk.Texture? art;
        public CodingAgent agent = CodingAgent.CLAUDE;

        public CompactItem (ItemKind kind) {
            this.kind = kind;
        }

        public static CompactItem glyph_item (string name, Rgba tint) {
            var item = new CompactItem (ItemKind.GLYPH);
            item.glyph = name;
            item.tint = tint;
            return item;
        }

        public static CompactItem text_item (string text, Rgba tint) {
            var item = new CompactItem (ItemKind.TEXT);
            item.text = text;
            item.tint = tint;
            return item;
        }

        public static CompactItem ring (double progress, Rgba tint) {
            var item = new CompactItem (ItemKind.RING);
            item.value = progress.clamp (0, 1);
            item.tint = tint;
            return item;
        }

        public static CompactItem level (double value, bool muted) {
            var item = new CompactItem (ItemKind.LEVEL);
            item.value = value.clamp (0, 1);
            item.flag = muted;
            return item;
        }

        public static CompactItem battery (double level, bool charging) {
            var item = new CompactItem (ItemKind.BATTERY);
            item.value = level.clamp (0, 1);
            item.flag = charging;
            return item;
        }

        public static CompactItem equalizer (bool playing) {
            var item = new CompactItem (ItemKind.EQUALIZER);
            item.flag = playing;
            return item;
        }

        public static CompactItem spinner () {
            return new CompactItem (ItemKind.SPINNER);
        }

        public static CompactItem art_item (Gdk.Texture? art) {
            var item = new CompactItem (ItemKind.ART);
            item.art = art;
            return item;
        }

        public static CompactItem agent_item (CodingAgent agent, bool attention) {
            var item = new CompactItem (ItemKind.AGENT);
            item.agent = agent;
            item.flag = attention;
            return item;
        }

        /* Whether the item moves by itself and needs a few frames a second while on show. */
        public bool is_animated () {
            return (kind == ItemKind.EQUALIZER && flag) || kind == ItemKind.SPINNER;
        }
    }

    /* Where an activity comes from, in the order the closed island prefers them when nothing is urgent. */
    public enum ActivitySource {
        AGENTS,
        TIMERS,
        SCRIPTS,
        MUSIC,
        AWAKE,
        OTHER;

        public static ActivitySource of (string id) {
            if (id == "agents") return AGENTS;
            if (id == "timer") return TIMERS;
            if (id.has_prefix ("api.")) return SCRIPTS;
            if (id == "media") return MUSIC;
            if (id == "awake") return AWAKE;
            return OTHER;
        }
    }

    public class Activity {
        public string id;
        public ActivityPriority priority;
        public CompactItem? leading;
        /* A few words between the two sides: the song, the project, the lyric being sung. */
        public string? middle;
        public Rgba middle_tint = Rgba (1, 1, 1, 0.92);
        public CompactItem? trailing;
        /* When it leaves by itself, in monotonic microseconds; 0 keeps it. */
        public int64 expires = 0;
        public int64 updated;

        public Activity (string id, ActivityPriority priority) {
            this.id = id;
            this.priority = priority;
            this.updated = get_monotonic_time ();
        }

        public bool is_animated () {
            return (leading != null && leading.is_animated ()) || (trailing != null && trailing.is_animated ());
        }
    }

    /* Every live activity, and the rule that picks the one the closed island shows: alerts and brief displays first,
     * the highest priority then the most recent; then the sources in order; within one, the highest priority, then
     * the most recent. */
    public class ActivityBoard {
        public HashTable<string, Activity> activities = new HashTable<string, Activity> (str_hash, str_equal);

        public void upsert (Activity activity) {
            activities[activity.id] = activity;
        }

        public void remove (string id) {
            activities.remove (id);
        }

        public bool prune (int64 now) {
            var expired = new GenericArray<string> ();
            activities.foreach ((id, activity) => {
                if (activity.expires != 0 && activity.expires <= now) {
                    expired.add (id);
                }
            });
            foreach (var id in expired) {
                activities.remove (id);
            }
            return expired.length > 0;
        }

        public Activity? current (int64 now) {
            Activity? urgent = null;
            Activity? best = null;
            activities.foreach ((id, activity) => {
                if (activity.expires != 0 && activity.expires <= now) {
                    return;
                }
                if (activity.priority >= ActivityPriority.ALERT) {
                    if (urgent == null || activity.priority > urgent.priority
                        || (activity.priority == urgent.priority && activity.updated > urgent.updated)) {
                        urgent = activity;
                    }
                    return;
                }
                if (best == null || better (activity, (!) best)) {
                    best = activity;
                }
            });
            return urgent ?? best;
        }

        static bool better (Activity a, Activity b) {
            var ra = ActivitySource.of (a.id), rb = ActivitySource.of (b.id);
            if (ra != rb) {
                return ra < rb;
            }
            if (a.priority != b.priority) {
                return a.priority > b.priority;
            }
            if (a.updated != b.updated) {
                return a.updated > b.updated;
            }
            return strcmp (a.id, b.id) < 0;
        }

        /* The next moment an activity expires, to wake up exactly then instead of polling; 0 when none will. */
        public int64 next_expiry (int64 now) {
            int64 next = 0;
            activities.foreach ((id, activity) => {
                if (activity.expires > now && (next == 0 || activity.expires < next)) {
                    next = activity.expires;
                }
            });
            return next;
        }
    }
}
