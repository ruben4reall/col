/* Connecting coding agents: Col's hooks in an agent's settings file, added or removed without touching anything else,
 * with a copy of the file kept beside it. The same entries as the Mac's `colctl hooks install`, calling the same
 * command line, so a settings file shared between a Mac and a Linux machine works on both. */

namespace Col {
    public errordomain HooksError {
        FAILED
    }

    public class HookEventSpec {
        public string name;
        /* Whether the event takes a tool matcher. */
        public bool matcher;
        /* Seconds the agent waits for the hook. */
        public int timeout;

        public HookEventSpec (string name, bool matcher, int timeout) {
            this.name = name;
            this.matcher = matcher;
            this.timeout = timeout;
        }
    }

    /* A coding agent Col connects to, where it keeps its hooks, and the events Col follows. */
    public class HookAgent {
        public CodingAgent agent;
        public string settings;
        public HookEventSpec[] events;

        HookAgent (CodingAgent agent, string settings, owned HookEventSpec[] events) {
            this.agent = agent;
            this.settings = settings;
            this.events = (owned) events;
        }

        public unowned string id () {
            return agent.id ();
        }

        public unowned string name () {
            return agent.display_name ();
        }

        public static HookAgent[] all () {
            return {
                new HookAgent (CodingAgent.CLAUDE, "~/.claude/settings.json", {
                    new HookEventSpec ("SessionStart", false, 5), new HookEventSpec ("UserPromptSubmit", false, 5),
                    new HookEventSpec ("PreToolUse", true, 5), new HookEventSpec ("PostToolUse", true, 5),
                    new HookEventSpec ("PermissionRequest", true, 120), new HookEventSpec ("Notification", false, 5),
                    new HookEventSpec ("Stop", false, 5), new HookEventSpec ("SessionEnd", false, 2),
                }),
                new HookAgent (CodingAgent.CODEX, "~/.codex/hooks.json", {
                    new HookEventSpec ("SessionStart", false, 5), new HookEventSpec ("UserPromptSubmit", false, 5),
                    new HookEventSpec ("PreToolUse", false, 5), new HookEventSpec ("PostToolUse", false, 5),
                    new HookEventSpec ("PermissionRequest", false, 120), new HookEventSpec ("Stop", false, 5),
                    new HookEventSpec ("SessionEnd", false, 2),
                }),
            };
        }

        public static HookAgent? named (string id) {
            foreach (var agent in all ()) {
                if (agent.id () == id) {
                    return agent;
                }
            }
            return null;
        }

        /* The command a hook runs: through ~/.local/bin, so moving or updating Col never breaks it. */
        public string command () {
            return agent == CodingAgent.CLAUDE
                ? "\"$HOME/.local/bin/colctl\" hook"
                : "\"$HOME/.local/bin/colctl\" hook --agent %s".printf (agent.id ());
        }

        public string settings_path () {
            return Paths.expand (settings);
        }

        /* Whether the agent is on this machine: its settings folder exists. */
        public bool is_present () {
            return FileUtils.test (Path.get_dirname (settings_path ()), FileTest.IS_DIR);
        }
    }

    namespace Hooks {
        public string link_path () {
            return Path.build_filename (Paths.home (), ".local", "bin", "colctl");
        }

        /* Whether a hook's command is Col's, under its name or Islet's (hooks written on a Mac before 2.0). */
        public bool calls_col (string? command) {
            if (command == null) {
                return false;
            }
            foreach (unowned string name in new string[] { "colctl", "islet" }) {
                if (command.contains (name + "\" hook") || command.has_suffix (name + " hook") || command.contains (name + " hook --agent")) {
                    return true;
                }
            }
            return false;
        }

        /* Whether a settings file, read as text, calls Col. */
        public bool mentions_col (string text) {
            foreach (unowned string name in new string[] { "colctl", "islet" }) {
                if (text.contains (name + "\\\" hook") || text.contains (name + "\" hook") || text.contains (name + " hook")) {
                    return true;
                }
            }
            return false;
        }

        /* True for an entry Col wrote: a matcher group holding Col's command. */
        public bool is_col_hook (Json.Node entry) {
            if (entry.get_node_type () != Json.NodeType.OBJECT) {
                return false;
            }
            var object = entry.get_object ();
            if (calls_col (JsonText.get_string (object, "command"))) {
                return true;
            }
            var hooks = JsonText.get_array (object, "hooks");
            if (hooks == null) {
                return false;
            }
            for (uint i = 0; i < hooks.get_length (); i++) {
                var hook = hooks.get_element (i);
                if (hook.get_node_type () == Json.NodeType.OBJECT && calls_col (JsonText.get_string (hook.get_object (), "command"))) {
                    return true;
                }
            }
            return false;
        }

        public Json.Node entry_for (HookAgent agent, HookEventSpec event) {
            var hook = new Json.Object ();
            hook.set_string_member ("type", "command");
            hook.set_string_member ("command", agent.command ());
            hook.set_int_member ("timeout", event.timeout);
            var hooks = new Json.Array ();
            hooks.add_object_element (hook);
            var group = new Json.Object ();
            if (event.matcher) {
                group.set_string_member ("matcher", "*");
            }
            group.set_array_member ("hooks", hooks);
            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (group);
            return node;
        }

        /* The file a settings path stands for: a link, as dotfile managers make, is followed, so the user's link stays a
         * link and their file is edited in place. */
        string resolved (string path) {
            var file = File.new_for_path (path);
            try {
                var info = file.query_info ("standard::is-symlink,standard::symlink-target", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                if (info.get_is_symlink ()) {
                    var real = Posix.realpath (path);
                    if (real != null) {
                        return real;
                    }
                }
            } catch (Error e) {
            }
            return path;
        }

        /* Writes a whole file under another name, readable as `mode`, then puts it in place: never half written. */
        public bool write_whole (string path, string contents, int mode) {
            var partial = "%s.col-%d".printf (path, (int) Posix.getpid ());
            Posix.unlink (partial);
            int fd = Posix.open (partial, Posix.O_WRONLY | Posix.O_CREAT | Posix.O_EXCL | Posix.O_NOFOLLOW | Posix.O_CLOEXEC, (Posix.mode_t) mode);
            if (fd < 0) {
                return false;
            }
            unowned uint8[] data = contents.data;
            size_t offset = 0;
            bool ok = true;
            while (offset < data.length) {
                ssize_t count = Posix.write (fd, (void*) ((uint8*) data + offset), data.length - offset);
                if (count < 0 && Posix.errno == Posix.EINTR) {
                    continue;
                }
                if (count <= 0) {
                    ok = false;
                    break;
                }
                offset += count;
            }
            // umask may have taken bits off: the mode asked for is the mode given.
            Posix.fchmod (fd, (Posix.mode_t) mode);
            if (Posix.fsync (fd) != 0) {
                ok = false;
            }
            Posix.close (fd);
            if (!ok || FileUtils.rename (partial, path) != 0) {
                Posix.unlink (partial);
                return false;
            }
            return true;
        }

        /* Keeps a copy of an agent's settings beside them, readable by its owner only: they can hold keys and tokens. */
        public void back_up (string contents, string path) {
            write_whole (path + ".col-backup", contents, 0600);
        }

        /* Points ~/.local/bin/colctl at this command. A link that already leads there is left as it is, a file of the
         * user's own is never replaced, and nothing is made when the command cannot be run. */
        public void link_command (string? colctl) {
            if (colctl == null || !FileUtils.test (colctl, FileTest.IS_EXECUTABLE)) {
                return;
            }
            var link = link_path ();
            var target = Posix.realpath (colctl) ?? colctl;
            var current = Posix.realpath (link);
            if (current != null && current == target) {
                return;
            }
            if (FileUtils.test (link, FileTest.EXISTS) && !FileUtils.test (link, FileTest.IS_SYMLINK)) {
                return;
            }
            if (FileUtils.test (link, FileTest.IS_SYMLINK)) {
                FileUtils.unlink (link);
            }
            DirUtils.create_with_parents (Path.get_dirname (link), 0755);
            FileUtils.symlink (target, link);
        }

        /* Adds or removes Col's hooks in an agent's settings, keeping everything else, in its order, and a backup. */
        public string edit (HookAgent agent, string? path, bool install, string? colctl) throws HooksError {
            var file_path = resolved (path != null ? Paths.expand ((!) path) : agent.settings_path ());
            string contents = "";
            Json.Object settings;
            int mode = 0600;
            bool existed = FileUtils.test (file_path, FileTest.EXISTS);
            if (existed) {
                try {
                    FileUtils.get_contents (file_path, out contents);
                } catch (FileError e) {
                    throw new HooksError.FAILED ("could not read %s: %s".printf (file_path, e.message));
                }
                Posix.Stat status;
                if (Posix.stat (file_path, out status) == 0) {
                    mode = (int) (status.st_mode & 0777);
                }
            }
            if (contents.strip () != "") {
                var parsed = JsonText.parse_object (contents);
                if (parsed == null) {
                    throw new HooksError.FAILED ("%s is not valid JSON; left untouched".printf (file_path));
                }
                settings = (!) parsed;
                back_up (contents, file_path);
            } else if (!install) {
                return "%s: nothing to remove.".printf (agent.name ());
            } else {
                settings = new Json.Object ();
            }
            var hooks = JsonText.get_object (settings, "hooks") ?? new Json.Object ();
            foreach (var event in agent.events) {
                var groups = new Json.Array ();
                var existing = JsonText.get_array (hooks, event.name);
                if (existing != null) {
                    for (uint i = 0; i < existing.get_length (); i++) {
                        var element = existing.get_element (i);
                        if (!is_col_hook (element)) {
                            groups.add_element (element.copy ());
                        }
                    }
                }
                if (install) {
                    groups.add_element (entry_for (agent, event));
                }
                if (groups.get_length () == 0) {
                    if (hooks.has_member (event.name)) {
                        hooks.remove_member (event.name);
                    }
                } else {
                    hooks.set_array_member (event.name, groups);
                }
            }
            if (hooks.get_size () == 0) {
                if (settings.has_member ("hooks")) {
                    settings.remove_member ("hooks");
                }
            } else {
                settings.set_object_member ("hooks", hooks);
            }
            if (install) {
                link_command (colctl);
            }
            DirUtils.create_with_parents (Path.get_dirname (file_path), 0700);
            var root = new Json.Node (Json.NodeType.OBJECT);
            root.set_object (settings);
            if (!write_whole (file_path, JsonText.pretty (root), mode)) {
                throw new HooksError.FAILED ("could not write %s".printf (file_path));
            }
            var message = install
                ? "%s: hooks installed in %s. New sessions report to Col.".printf (agent.name (), file_path)
                : "%s: Col's hooks removed from %s.".printf (agent.name (), file_path);
            if (agent.agent == CodingAgent.CODEX && install) {
                message += " Codex asks you to review new hooks once: run /hooks in Codex and trust Col's.";
            }
            return message;
        }

        /* Whether an agent's settings call Col. */
        public bool is_connected (HookAgent agent, string? path = null) {
            var file_path = path != null ? Paths.expand ((!) path) : agent.settings_path ();
            string text;
            try {
                if (!FileUtils.get_contents (file_path, out text)) {
                    return false;
                }
            } catch (FileError e) {
                return false;
            }
            return mentions_col (text);
        }
    }
}
