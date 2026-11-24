/* `col --demo <state>`: the island in a given state with made-up content, still, for screenshots. Nothing of the
 * user's is read: no player, no agent, no clipboard, no settings file. */

namespace Col.Demo {
    public const string STATES = "collapsed, peek, music, music-closed, lyrics, lyrics-closed, agent, agent-permission, volume, timer, tools, battery, settings";

    const string LRC = """[00:00.00]
[00:41.20]Golden light across the water
[00:45.60]Windows down and nowhere to be
[00:50.10]Into the blue we drive forever
[00:54.40]Hold the light, hold it close to me
[00:58.90]Every road is ours tonight
[01:03.30]Every song a little brighter
""";

    /* A cover painted here: a sun setting over hills. */
    Gdk.Texture cover () {
        int size = 192;
        var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, size, size);
        var cr = new Cairo.Context (surface);
        var sky = new Cairo.Pattern.linear (0, 0, 0, size);
        sky.add_color_stop_rgb (0, 0.98, 0.62, 0.42);
        sky.add_color_stop_rgb (0.55, 0.86, 0.36, 0.42);
        sky.add_color_stop_rgb (1, 0.36, 0.2, 0.42);
        cr.set_source (sky);
        cr.paint ();
        cr.set_source_rgba (1, 0.93, 0.8, 0.95);
        cr.arc (size * 0.56, size * 0.5, size * 0.12, 0, 2 * Math.PI);
        cr.fill ();
        double[,] hills = { { 0.62, 0.42, 0.24, 0.5 }, { 0.72, 0.3, 0.17, 0.42 }, { 0.84, 0.2, 0.12, 0.3 } };
        for (int i = 0; i < 3; i++) {
            cr.set_source_rgb (hills[i, 1], hills[i, 2], hills[i, 3]);
            cr.move_to (0, size * hills[i, 0]);
            cr.curve_to (size * 0.3, size * (hills[i, 0] - 0.08), size * 0.6, size * (hills[i, 0] + 0.06), size, size * (hills[i, 0] - 0.04));
            cr.line_to (size, size);
            cr.line_to (0, size);
            cr.close_path ();
            cr.fill ();
        }
        surface.flush ();
        var data = new uint8[surface.get_stride () * size];
        Memory.copy (data, surface.get_data (), data.length);
        return new Gdk.MemoryTexture (size, size, Gdk.MemoryFormat.B8G8R8A8_PREMULTIPLIED, new Bytes (data), surface.get_stride ());
    }

    NowPlaying song () {
        var media = new NowPlaying ();
        media.title = "Golden Hour";
        media.artist = "Sunset Avenue";
        media.album = "Long Days";
        media.player = "Music";
        media.duration = 213;
        media.position = 47.2;
        media.timestamp = get_monotonic_time ();
        // Still: the position does not move.
        media.rate = 0;
        media.playing = true;
        media.can_seek = true;
        media.art = cover ();
        return media;
    }

    void permission (Model model) {
        var raw = JsonText.parse_object ("""{
            "session_id": "demo", "hook_event_name": "PermissionRequest", "cwd": "/home/you/col",
            "tool_name": "Bash", "tool_input": {"command": "git push origin main", "description": "Push the release"}
        }""");
        var event = CodingAgent.CLAUDE.event_from ((!) raw);
        model.agents.receive ((!) event, (decision) => {});
    }

    void working (Model model) {
        var raw = JsonText.parse_object ("""{
            "session_id": "demo", "hook_event_name": "PreToolUse", "cwd": "/home/you/col",
            "tool_name": "Edit", "tool_input": {"file_path": "/home/you/col/linux/src/app/island-view.vala"}
        }""");
        model.agents.receive ((!) CodingAgent.CLAUDE.event_from ((!) raw), (decision) => {});
    }

    /* The states that move: the intro, and the README's film. */
    public const string MOVING = "intro, showcase";

    public bool is_known (string state) {
        foreach (unowned string known in (STATES + ", " + MOVING).split (", ")) {
            if (known == state) {
                return true;
            }
        }
        return false;
    }

    /* `--demo intro` plays the intro without its chime; `--demo showcase` is the README's film: the intro, a song in
     * the closed island, the island open on its lyrics, closed again. Both move, so neither is frozen. */
    void showcase (Model model, IslandView view, bool film) {
        model.settings.volume_display = true;
        model.settings.lyrics = true;
        if (!film) {
            view.play_intro (false);
            return;
        }
        Timeout.add (3000, () => {
            view.play_intro (false);
            return Source.REMOVE;
        });
        Timeout.add (6500, () => {
            var media = song ();
            media.rate = 1;
            model.set_media (media);
            model.set_lyrics (Lyrics.parse (LRC), media.track_key ());
            return Source.REMOVE;
        });
        Timeout.add (9000, () => {
            view.held_open = true;
            view.expanded.show_page ("music");
            view.open ();
            return Source.REMOVE;
        });
        Timeout.add (12000, () => {
            view.held_open = false;
            view.close ();
            return Source.REMOVE;
        });
    }

    public void apply (Model model, IslandView view, string state) {
        if (state == "intro" || state == "showcase") {
            showcase (model, view, state == "showcase");
            return;
        }
        model.frozen = true;
        view.frozen = true;
        view.expanded.music.freeze ();
        var settings = model.settings;
        settings.lyrics = state == "lyrics" || state == "lyrics-closed";
        settings.lyrics_in_closed = state == "lyrics-closed";
        settings.volume_display = true;

        switch (state) {
        case "collapsed":
        case "peek":
            view.force_visible = true;
            break;
        case "music":
        case "music-closed":
        case "lyrics":
        case "lyrics-closed":
            var media = song ();
            model.set_media (media);
            if (settings.lyrics) {
                model.set_lyrics (Lyrics.parse (LRC), media.track_key ());
            }
            break;
        case "agent":
            working (model);
            break;
        case "agent-permission":
            permission (model);
            break;
        case "volume":
            model.show_volume (0.62, false);
            break;
        case "timer":
            model.timer.frozen_remaining = 272;
            model.timer.changed ();
            break;
        case "tools":
            model.timer.frozen_remaining = 272;
            model.timer.changed ();
            model.clipboard.add ("https://github.com/ruben4reall/col");
            model.clipboard.add ("colctl hooks install --agent claude");
            model.clipboard.add ("Meet at the station at 7:40, platform 3");
            model.set_awake (true);
            break;
        case "settings":
            view.force_visible = true;
            model.settings_requested ();
            break;
        case "battery":
            model.battery_present = true;
            model.battery_level = 0.15;
            model.set_battery (true, 0.86, true);
            break;
        default:
            break;
        }

        bool open = state == "music" || state == "lyrics" || state == "agent-permission" || state == "tools";
        if (open) {
            view.held_open = true;
            view.expanded.show_page (state == "agent-permission" ? "live" : (state == "tools" ? "tools" : "music"));
            view.open ();
        } else if (state == "peek") {
            view.move_to (IslandState.PEEK);
        } else {
            view.move_to (view.rest_state ());
        }
    }
}
