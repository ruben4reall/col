/* What Col fetches: the lyrics of the song playing, from LRCLIB while lyrics are on, and the cover the player points
 * to. Both are kept in $XDG_CACHE_HOME/col so a song is asked once. */

namespace Col {
    /* The bytes of an answer as text, ended as C strings are. */
    public string bytes_text (Bytes bytes) {
        var array = new ByteArray.sized ((uint) bytes.get_size () + 1);
        array.append (bytes.get_data ());
        array.append ({ 0 });
        return ((string) array.data).dup ();
    }

    public string user_agent () {
        return "Col %s (https://github.com/ruben4reall/col)".printf (Config.VERSION);
    }

    /* Covers: a file the player wrote (file://), or an address it gave (http, https), downloaded once and kept small. */
    public class ArtLoader : Object {
        Soup.Session session;
        /* The last few covers, in memory. */
        HashTable<string, Gdk.Texture> memory = new HashTable<string, Gdk.Texture> (str_hash, str_equal);
        GenericArray<string> order = new GenericArray<string> ();
        const int SIDE = 192;

        public ArtLoader () {
            session = new Soup.Session ();
            session.user_agent = user_agent ();
            session.timeout = 10;
        }

        string folder () {
            return Path.build_filename (Paths.cache_dir (), "art");
        }

        public Gdk.Texture? cached (string url) {
            return url == "" ? null : memory[url];
        }

        void remember (string url, Gdk.Texture texture) {
            memory[url] = texture;
            order.add (url);
            while (order.length > 4) {
                memory.remove (order[0]);
                order.remove_index (0);
            }
        }

        public async Gdk.Texture? load (string url) {
            var known = cached (url);
            if (known != null) {
                return known;
            }
            Bytes? bytes = null;
            if (url.has_prefix ("file://")) {
                try {
                    uint8[] contents;
                    yield File.new_for_uri (url).load_contents_async (null, out contents, null);
                    bytes = new Bytes (contents);
                } catch (Error e) {
                    return null;
                }
            } else if (url.has_prefix ("https://") || url.has_prefix ("http://")) {
                var file = Path.build_filename (folder (), Paths.digest (url));
                try {
                    uint8[] contents;
                    if (FileUtils.get_data (file, out contents)) {
                        bytes = new Bytes (contents);
                    }
                } catch (FileError e) {
                }
                if (bytes == null) {
                    try {
                        var message = new Soup.Message ("GET", url);
                        bytes = yield session.send_and_read_async (message, Priority.LOW, null);
                        if (message.status_code != 200 || bytes.get_size () == 0 || bytes.get_size () > 8 * 1024 * 1024) {
                            return null;
                        }
                        DirUtils.create_with_parents (folder (), 0700);
                        FileUtils.set_data (file, bytes.get_data ());
                        prune ();
                    } catch (Error e) {
                        return null;
                    }
                }
            } else {
                return null;
            }
            var texture = yield decode ((!) bytes);
            if (texture != null) {
                remember (url, (!) texture);
            }
            return texture;
        }

        /* Decoded at the size the island draws it, so a large cover does not sit in memory at full size. */
        async Gdk.Texture? decode (Bytes bytes) {
            try {
                var stream = new MemoryInputStream.from_bytes (bytes);
                var pixbuf = yield new Gdk.Pixbuf.from_stream_at_scale_async (stream, SIDE, SIDE, true, null);
                return Gdk.Texture.for_pixbuf (pixbuf);
            } catch (Error e) {
                return null;
            }
        }

        /* Keeps the 200 most recent covers. */
        void prune () {
            try {
                var dir = Dir.open (folder ());
                var files = new GenericArray<string> ();
                string? name;
                while ((name = dir.read_name ()) != null) {
                    files.add (Path.build_filename (folder (), (!) name));
                }
                if (files.length <= 200) {
                    return;
                }
                files.sort ((a, b) => {
                    Posix.Stat sa, sb;
                    Posix.stat (a, out sa);
                    Posix.stat (b, out sb);
                    return (int) (sa.st_mtime - sb.st_mtime);
                });
                for (int i = 0; i < files.length - 200; i++) {
                    FileUtils.unlink (files[i]);
                }
            } catch (FileError e) {
            }
        }
    }

    public enum LyricsAnswer {
        FOUND,
        INSTRUMENTAL,
        NOT_FOUND,
        /* The database could not be reached, or asked to wait: try again later. */
        UNAVAILABLE
    }

    /* Finds the lyrics of a track: a .lrc file of the user's first, then LRCLIB, an open database that needs no account.
     * Only the title, the artist, the album and the length of the track are sent. Answers are kept on disk, misses
     * for a week. */
    public class LyricsService : Object {
        Soup.Session session;
        /* LRCLIB asks clients to slow down with a 429 and a Retry-After: nothing is asked before this moment. */
        int64 quiet_until = 0;
        const string BASE = "https://lrclib.net/api";
        const int64 MISS_LIFETIME = 7 * 24 * 3600;

        public LyricsService () {
            session = new Soup.Session ();
            session.user_agent = user_agent ();
            session.timeout = 8;
        }

        /* Where the user's own `Artist - Title.lrc` files take precedence. */
        public static string user_folder () {
            return Path.build_filename (Paths.data_dir (), "lyrics");
        }

        public static string cache_folder () {
            return Path.build_filename (Paths.cache_dir (), "lyrics");
        }

        public async LyricsAnswer lookup (LyricsQuery query, out Lyrics? lyrics) {
            lyrics = user_lyrics (query);
            if (lyrics != null) {
                return LyricsAnswer.FOUND;
            }
            var key = query.cache_key ();
            var cached_answer = cached (key, out lyrics);
            if (cached_answer != LyricsAnswer.UNAVAILABLE) {
                return cached_answer;
            }
            if (quiet_until > get_real_time ()) {
                return LyricsAnswer.UNAVAILABLE;
            }
            Json.Object? record;
            var answer = yield fetch (query, out lyrics, out record);
            if (answer != LyricsAnswer.UNAVAILABLE) {
                store (key, record);
            }
            if (Environment.get_variable ("COL_DEBUG") != null) {
                stderr.printf ("lyrics: %s - %s: %s\n", query.main_artist (), query.clean_title (), answer.to_string ());
            }
            return answer;
        }

        Lyrics? user_lyrics (LyricsQuery query) {
            var wanted = "%s - %s".printf (query.main_artist (), query.clean_title ()).down ();
            try {
                var dir = Dir.open (user_folder ());
                string? name;
                while ((name = dir.read_name ()) != null) {
                    if (!((!) name).down ().has_suffix (".lrc")) {
                        continue;
                    }
                    var stem = ((!) name).substring (0, ((!) name).length - 4).down ();
                    if (stem != wanted) {
                        continue;
                    }
                    string text;
                    FileUtils.get_contents (Path.build_filename (user_folder (), (!) name), out text);
                    return Lyrics.parse (text) ?? Lyrics.plain (text);
                }
            } catch (Error e) {
            }
            return null;
        }

        async LyricsAnswer fetch (LyricsQuery query, out Lyrics? lyrics, out Json.Object? record) {
            lyrics = null;
            record = null;
            // The exact track first, then a search that tolerates a different album or spelling.
            var exact = new StringBuilder (BASE + "/get?track_name=");
            exact.append (Uri.escape_string (query.clean_title (), null, false));
            exact.append ("&artist_name=");
            exact.append (Uri.escape_string (query.main_artist (), null, false));
            if (query.album != "") {
                exact.append ("&album_name=");
                exact.append (Uri.escape_string (query.album, null, false));
            }
            if (query.duration > 0) {
                exact.append ("&duration=%d".printf ((int) Math.round (query.duration)));
            }
            int status;
            var body = yield request (exact.str, out status);
            if (status == 200) {
                record = JsonText.parse_object (body ?? "");
                if (record != null) {
                    return answer_from ((!) record, out lyrics);
                }
            } else if (status != 404) {
                return LyricsAnswer.UNAVAILABLE;
            }
            var search = "%s/search?track_name=%s&artist_name=%s".printf (BASE,
                Uri.escape_string (query.clean_title (), null, false), Uri.escape_string (query.main_artist (), null, false));
            body = yield request (search, out status);
            if (status == 404) {
                return LyricsAnswer.NOT_FOUND;
            }
            if (status != 200) {
                return LyricsAnswer.UNAVAILABLE;
            }
            var node = JsonText.parse (body ?? "");
            if (node == null || node.get_node_type () != Json.NodeType.ARRAY) {
                return LyricsAnswer.NOT_FOUND;
            }
            Json.Object? best = null;
            var array = node.get_array ();
            for (uint i = 0; i < array.get_length (); i++) {
                var item = array.get_element (i);
                if (item.get_node_type () != Json.NodeType.OBJECT) {
                    continue;
                }
                var candidate = item.get_object ();
                double duration;
                if (!JsonText.get_double (candidate, "duration", out duration)) {
                    duration = -1;
                }
                if (!query.matches (duration)) {
                    continue;
                }
                var synced = JsonText.get_string (candidate, "syncedLyrics");
                // Synced lyrics beat plain ones.
                if (synced != null && synced != "") {
                    best = candidate;
                    break;
                }
                if (best == null) {
                    best = candidate;
                }
            }
            if (best == null) {
                return LyricsAnswer.NOT_FOUND;
            }
            record = best;
            return answer_from ((!) best, out lyrics);
        }

        static LyricsAnswer answer_from (Json.Object record, out Lyrics? lyrics) {
            lyrics = null;
            if (JsonText.get_bool (record, "instrumental", false)) {
                return LyricsAnswer.INSTRUMENTAL;
            }
            var synced = JsonText.get_string (record, "syncedLyrics");
            if (synced != null) {
                lyrics = Lyrics.parse ((!) synced);
                if (lyrics != null) {
                    return LyricsAnswer.FOUND;
                }
            }
            var plain = JsonText.get_string (record, "plainLyrics");
            if (plain != null) {
                lyrics = Lyrics.plain ((!) plain);
                if (lyrics != null) {
                    return LyricsAnswer.FOUND;
                }
            }
            return LyricsAnswer.NOT_FOUND;
        }

        async string? request (string url, out int status) {
            status = 0;
            try {
                var message = new Soup.Message ("GET", url);
                var bytes = yield session.send_and_read_async (message, Priority.DEFAULT, null);
                status = (int) message.status_code;
                if (status == 429) {
                    var retry = message.response_headers.get_one ("Retry-After");
                    int64 wait = 60;
                    if (retry != null) {
                        int64.try_parse ((!) retry, out wait);
                    }
                    quiet_until = get_real_time () + wait.clamp (5, 3600) * 1000000;
                }
                if (bytes == null) {
                    return null;
                }
                return bytes_text ((!) bytes);
            } catch (Error e) {
                return null;
            }
        }

        static string cache_file (string key) {
            return Path.build_filename (cache_folder (), Paths.digest (key) + ".json");
        }

        static LyricsAnswer cached (string key, out Lyrics? lyrics) {
            lyrics = null;
            string text;
            try {
                if (!FileUtils.get_contents (cache_file (key), out text)) {
                    return LyricsAnswer.UNAVAILABLE;
                }
            } catch (FileError e) {
                return LyricsAnswer.UNAVAILABLE;
            }
            var entry = JsonText.parse_object (text);
            if (entry == null) {
                return LyricsAnswer.UNAVAILABLE;
            }
            if (JsonText.get_bool (entry, "instrumental", false)) {
                return LyricsAnswer.INSTRUMENTAL;
            }
            var synced = JsonText.get_string (entry, "synced");
            if (synced != null && (lyrics = Lyrics.parse ((!) synced)) != null) {
                return LyricsAnswer.FOUND;
            }
            var plain = JsonText.get_string (entry, "plain");
            if (plain != null && (lyrics = Lyrics.plain ((!) plain)) != null) {
                return LyricsAnswer.FOUND;
            }
            // A miss is asked again after a week: someone may have added the lyrics since.
            double fetched;
            JsonText.get_double (entry, "fetched", out fetched);
            return get_real_time () / 1000000 - (int64) fetched < MISS_LIFETIME ? LyricsAnswer.NOT_FOUND : LyricsAnswer.UNAVAILABLE;
        }

        /* Keeps a record as LRCLIB gave it, or a miss when there is none. */
        static void store (string key, Json.Object? record) {
            var entry = new Json.Object ();
            var synced = JsonText.get_string (record, "syncedLyrics");
            var plain = JsonText.get_string (record, "plainLyrics");
            if (synced != null) {
                entry.set_string_member ("synced", synced);
            }
            if (plain != null) {
                entry.set_string_member ("plain", plain);
            }
            entry.set_boolean_member ("instrumental", JsonText.get_bool (record, "instrumental", false));
            entry.set_int_member ("fetched", get_real_time () / 1000000);
            DirUtils.create_with_parents (cache_folder (), 0700);
            var root = new Json.Node (Json.NodeType.OBJECT);
            root.set_object (entry);
            Hooks.write_whole (cache_file (key), JsonText.compact (root, false), 0600);
        }

        public static void clear_cache () {
            try {
                var dir = Dir.open (cache_folder ());
                string? name;
                while ((name = dir.read_name ()) != null) {
                    FileUtils.unlink (Path.build_filename (cache_folder (), (!) name));
                }
            } catch (FileError e) {
            }
        }
    }

    /* Looks up the lyrics of each new song while lyrics are on, and hands them to the model. */
    public class LyricsFollower : Object {
        Model model;
        LyricsService service = new LyricsService ();
        string asked = "";
        uint retry = 0;

        public LyricsFollower (Model model) {
            this.model = model;
            model.media_changed.connect (follow);
            model.settings.changed.connect ((key) => {
                if (key == "lyrics") {
                    asked = "";
                    follow ();
                }
            });
        }

        void follow () {
            var media = model.media;
            if (media == null || media.is_empty () || !model.settings.lyrics) {
                return;
            }
            var key = media.track_key ();
            if (key == asked) {
                return;
            }
            asked = key;
            if (model.lyrics_track != key) {
                model.set_lyrics (null, key);
            }
            var query = new LyricsQuery (media.title, media.artist, media.album, media.duration);
            service.lookup.begin (query, (obj, result) => {
                Lyrics? lyrics;
                var answer = service.lookup.end (result, out lyrics);
                if (model.media == null || model.media.track_key () != key) {
                    return;
                }
                if (answer == LyricsAnswer.UNAVAILABLE) {
                    // Asked again on the next change of track, or in a minute for this one.
                    asked = "";
                    if (retry == 0) {
                        retry = Timeout.add_seconds (60, () => {
                            retry = 0;
                            follow ();
                            return Source.REMOVE;
                        });
                    }
                    return;
                }
                model.set_lyrics (lyrics, key);
            });
        }
    }
}
