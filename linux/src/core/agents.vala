/* Coding agents: their hook events, the sessions they make, and the answers their hooks expect. The same rules as
 * ColCore's Agents.swift and CodingAgents.swift, so an agent behaves the same beside a Mac's notch and a Linux island. */

namespace Col {
    public enum CodingAgent {
        CLAUDE,
        CODEX,
        GEMINI,
        CURSOR,
        COPILOT;

        public static bool parse (string? id, out CodingAgent agent) {
            agent = CLAUDE;
            switch (id) {
            case "claude": agent = CLAUDE; return true;
            case "codex": agent = CODEX; return true;
            case "gemini": agent = GEMINI; return true;
            case "cursor": agent = CURSOR; return true;
            case "copilot": agent = COPILOT; return true;
            default: return false;
            }
        }

        /* The agent behind a session, from the name the session keeps. */
        public static bool from_name (string? name, out CodingAgent agent) {
            agent = CLAUDE;
            foreach (var candidate in all ()) {
                if (candidate.display_name () == name) {
                    agent = candidate;
                    return true;
                }
            }
            return false;
        }

        public static CodingAgent[] all () {
            return { CLAUDE, CODEX, GEMINI, CURSOR, COPILOT };
        }

        public unowned string id () {
            switch (this) {
            case CODEX: return "codex";
            case GEMINI: return "gemini";
            case CURSOR: return "cursor";
            case COPILOT: return "copilot";
            default: return "claude";
            }
        }

        public unowned string display_name () {
            switch (this) {
            case CODEX: return "Codex";
            case GEMINI: return "Gemini CLI";
            case CURSOR: return "Cursor";
            case COPILOT: return "GitHub Copilot (VS Code)";
            default: return "Claude Code";
            }
        }

        /* Agents whose hooks can wait for an answer: their permission requests get Allow and Deny in the island. */
        public bool answers_permissions () {
            return this == CLAUDE || this == CODEX;
        }

        /* False for an agent that never says a session is over (VS Code sends no event when a Copilot chat ends). */
        public bool ends_sessions () {
            return this != COPILOT;
        }

        /* Turns one hook payload, as this agent wrote it, into an event. Null for events Col does not follow. */
        public HookEvent? event_from (Json.Object raw) {
            switch (this) {
            case CLAUDE:
            case CODEX:
                var session = JsonText.get_string (raw, "session_id");
                var name = JsonText.get_string (raw, "hook_event_name");
                if (session == null || name == null) {
                    return null;
                }
                var event = new HookEvent (session, name);
                event.cwd = JsonText.get_string (raw, "cwd");
                event.tool_name = JsonText.get_string (raw, "tool_name");
                event.tool_input = JsonText.get_object (raw, "tool_input");
                event.notification_type = JsonText.get_string (raw, "notification_type");
                event.message = JsonText.get_string (raw, "message");
                event.agent_name = JsonText.get_string (raw, "agent_name");
                if (event.agent_name == null) {
                    event.set_agent (this);
                }
                return event;
            case GEMINI:
                var session = JsonText.get_string (raw, "session_id");
                var name = translate_gemini (JsonText.get_string (raw, "hook_event_name"));
                if (session == null || name == null) {
                    return null;
                }
                var event = new HookEvent (session, name);
                event.cwd = JsonText.get_string (raw, "cwd");
                event.tool_name = JsonText.get_string (raw, "tool_name");
                event.tool_input = JsonText.get_object (raw, "tool_input");
                var notice = JsonText.get_string (raw, "notification_type");
                // Gemini asks for a tool's confirmation in the terminal and tells its hooks with a ToolPermission notice.
                event.notification_type = notice == "ToolPermission" ? "permission_prompt" : notice;
                event.message = JsonText.get_string (raw, "message");
                event.set_agent (this);
                return event;
            case CURSOR:
                var session = JsonText.get_string (raw, "conversation_id");
                var name = JsonText.get_string (raw, "hook_event_name");
                if (session == null || name == null) {
                    return null;
                }
                string? cwd = null;
                var roots = JsonText.get_array (raw, "workspace_roots");
                if (roots != null && roots.get_length () > 0) {
                    var first = roots.get_element (0);
                    if (first.get_node_type () == Json.NodeType.VALUE && first.get_value_type () == typeof (string)) {
                        cwd = first.get_string ();
                    }
                }
                if (cwd == null) {
                    cwd = JsonText.get_string (raw, "cwd");
                }
                var event = new HookEvent (session, "");
                event.cwd = cwd;
                event.set_agent (this);
                switch (name) {
                case "sessionStart": event.event_name = "SessionStart"; break;
                case "sessionEnd": event.event_name = "SessionEnd"; break;
                case "beforeSubmitPrompt": event.event_name = "UserPromptSubmit"; break;
                case "stop": event.event_name = "Stop"; break;
                case "postToolUse":
                    event.event_name = "PostToolUse";
                    event.tool_name = JsonText.get_string (raw, "tool_name");
                    event.tool_input = JsonText.get_object (raw, "tool_input");
                    break;
                case "afterShellExecution":
                    event.event_name = "PostToolUse";
                    event.tool_name = "Shell";
                    var command = JsonText.get_string (raw, "command");
                    if (command != null) {
                        event.tool_input = new Json.Object ();
                        event.tool_input.set_string_member ("command", command);
                    }
                    break;
                case "afterFileEdit":
                    event.event_name = "PostToolUse";
                    event.tool_name = "Edit";
                    var file = JsonText.get_string (raw, "file_path");
                    if (file != null) {
                        event.tool_input = new Json.Object ();
                        event.tool_input.set_string_member ("file_path", file);
                    }
                    break;
                default:
                    return null;
                }
                return event;
            default:
                // VS Code's own hooks (the Local agent).
                var name = JsonText.get_string (raw, "hook_event_name");
                if (name == null) {
                    return null;
                }
                var session = JsonText.get_string (raw, "session_id") ?? JsonText.get_string (raw, "transcript_path")
                    ?? JsonText.get_string (raw, "cwd") ?? "vscode-copilot";
                var event = new HookEvent (session, name);
                event.cwd = JsonText.get_string (raw, "cwd");
                event.tool_name = JsonText.get_string (raw, "tool_name");
                event.tool_input = JsonText.get_object (raw, "tool_input");
                event.message = JsonText.get_string (raw, "message");
                event.set_agent (this);
                return event;
            }
        }

        static string? translate_gemini (string? name) {
            switch (name) {
            case "SessionStart": return "SessionStart";
            case "SessionEnd": return "SessionEnd";
            case "BeforeAgent": return "UserPromptSubmit";
            case "BeforeTool": return "PreToolUse";
            case "AfterTool": return "PostToolUse";
            case "AfterAgent": return "Stop";
            case "Notification": return "Notification";
            default: return null;
            }
        }

        /* What a hook prints when Col has nothing to say, so the agent carries on as usual. Null prints nothing. */
        public string? neutral_output (string event_name) {
            switch (this) {
            case GEMINI: return "{}";
            case CURSOR: return event_name == "beforeSubmitPrompt" ? "{\"continue\":true}" : "{}";
            case COPILOT: return event_name == "PreToolUse" ? "{}" : null;
            default: return null;
            }
        }
    }

    /* What the island answers a permission request. */
    public enum Decision {
        ALLOW,
        DENY,
        /* Let the agent ask in the terminal, as if Col were not there. */
        ASK;

        public unowned string to_key () {
            switch (this) {
            case ALLOW: return "allow";
            case DENY: return "deny";
            default: return "ask";
            }
        }

        /* The hook output Claude Code and Codex read for a decision; null for "ask", which prints nothing. */
        public string? hook_output () {
            switch (this) {
            case ALLOW:
                return "{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\"}}}";
            case DENY:
                return "{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"deny\",\"message\":\"Denied from Col.\"}}}";
            default:
                return null;
            }
        }
    }

    /* A coding agent's hook event, in the shape Claude Code and Codex write on a hook's stdin. */
    public class HookEvent {
        public string session_id;
        public string event_name;
        public string? cwd;
        public string? tool_name;
        public Json.Object? tool_input;
        public string? notification_type;
        public string? message;
        /* Set by agents without hooks, through `colctl agent`: their name stands for the project. */
        public string? agent_name;
        public bool has_agent = false;
        public CodingAgent agent = CodingAgent.CLAUDE;

        public HookEvent (string session_id, string event_name) {
            this.session_id = session_id;
            this.event_name = event_name;
        }

        public void set_agent (CodingAgent agent) {
            this.agent = agent;
            this.has_agent = true;
        }

        /* The project, named after the folder the session runs in. */
        public string project () {
            if (agent_name != null && agent_name != "") {
                return agent_name;
            }
            if (cwd == null || cwd == "") {
                return has_agent ? agent.display_name () : "Agent";
            }
            var trimmed = cwd;
            while (trimmed.length > 1 && trimmed.has_suffix ("/")) {
                trimmed = trimmed.substring (0, trimmed.length - 1);
            }
            return Path.get_basename (trimmed);
        }

        /* Tool names across agents, shown the way people read them. */
        public static unowned string label_for (string tool) {
            switch (tool) {
            case "run_shell_command":
            case "shell":
                return "Shell";
            case "write_file": return "Write";
            case "replace": return "Edit";
            case "read_file":
            case "read_many_files":
                return "Read";
            case "web_fetch": return "Fetch";
            case "google_web_search": return "Search";
            case "search_file_content": return "Grep";
            case "list_directory": return "List";
            case "apply_patch": return "Patch";
            default: return tool;
            }
        }

        public static bool is_shell (string? tool) {
            return tool == "Bash" || tool == "Shell" || tool == "run_shell_command" || tool == "shell";
        }

        public string? tool_label () {
            return tool_name != null ? label_for (tool_name) : null;
        }

        string? input_string (string key) {
            return JsonText.get_string (tool_input, key);
        }

        string? input_file (string key) {
            var value = input_string (key);
            return value != null ? Path.get_basename (value) : null;
        }

        string? input_first_line (string key) {
            var value = input_string (key);
            if (value == null) {
                return null;
            }
            foreach (unowned string line in value.split ("\n")) {
                if (line != "") {
                    return line;
                }
            }
            return value;
        }

        static string prefix (string text, int characters) {
            if (text.char_count () <= characters) {
                return text;
            }
            return text.substring (0, text.index_of_nth_char (characters));
        }

        /* A short line saying what the tool is about to do: the command for a shell, the file for edits. */
        public string? tool_summary () {
            if (tool_name == null) {
                return null;
            }
            string? detail = null;
            if (is_shell (tool_name)) {
                detail = input_string ("description") ?? input_first_line ("command");
            } else {
                switch (tool_name) {
                case "Edit":
                case "Write":
                case "Read":
                case "NotebookEdit":
                case "MultiEdit":
                    detail = input_file ("file_path") ?? input_file ("notebook_path");
                    break;
                case "Grep":
                case "Glob":
                    detail = input_string ("pattern");
                    break;
                case "WebFetch":
                case "web_fetch":
                    var url = input_string ("url");
                    if (url != null) {
                        try {
                            var uri = Uri.parse (url, UriFlags.NONE);
                            detail = uri.get_host ();
                        } catch (UriError e) {
                        }
                    }
                    if (detail == null) {
                        detail = input_string ("prompt");
                    }
                    break;
                case "WebSearch":
                case "google_web_search":
                    detail = input_string ("query");
                    break;
                case "Agent":
                case "Task":
                    detail = input_string ("description");
                    break;
                default:
                    detail = input_first_line ("command") ?? input_file ("file_path") ?? input_file ("absolute_path")
                        ?? input_file ("path") ?? input_string ("pattern") ?? input_string ("query");
                    break;
                }
            }
            var label = label_for (tool_name);
            if (detail == null || detail == "") {
                return label;
            }
            return "%s · %s".printf (label, prefix (detail, 70));
        }

        /* What a permission request is for, in a line, never in the agent's own words: a shell request names the
         * command itself, since the description an agent gives can say anything. */
        public string? request_summary () {
            if (tool_name == null || !is_shell (tool_name)) {
                return tool_summary ();
            }
            var label = tool_label () ?? tool_name;
            var command = input_string ("command");
            if (command == null) {
                return label;
            }
            foreach (unowned string line in command.split ("\n")) {
                if (line.strip () != "") {
                    return "%s · %s".printf (label, prefix (line.strip (), 70));
                }
            }
            return label;
        }

        /* What a permission request approves, whole: the command for a shell, the file for the tools that read or change
         * one, the address for a fetch, or every argument for any other tool. */
        public string? tool_detail () {
            if (tool_input == null || tool_input.get_size () == 0) {
                return null;
            }
            foreach (unowned string key in target_keys ()) {
                var value = input_string (key);
                if (value != null) {
                    return value;
                }
            }
            return arguments (tool_input);
        }

        string[] target_keys () {
            if (tool_name == null) {
                return {};
            }
            if (is_shell (tool_name)) {
                return { "command" };
            }
            switch (tool_name) {
            case "Edit":
            case "MultiEdit":
            case "Write":
            case "Read":
            case "write_file":
            case "replace":
            case "read_file":
                return { "file_path", "absolute_path" };
            case "NotebookEdit":
                return { "notebook_path" };
            case "WebFetch":
            case "web_fetch":
                return { "url" };
            default:
                return {};
            }
        }

        /* Every argument, a line each, in the order of their names: text as it is, anything else as JSON. */
        public static string arguments (Json.Object input) {
            var names = new GenericArray<string> ();
            foreach (unowned string name in input.get_members ()) {
                names.add (name);
            }
            names.sort ((a, b) => strcmp (a, b));
            var lines = new GenericArray<string> ();
            foreach (var name in names) {
                var node = input.get_member (name);
                string shown;
                if (node.get_node_type () == Json.NodeType.VALUE && node.get_value_type () == typeof (string)) {
                    shown = node.get_string ();
                } else {
                    shown = JsonText.compact (node, true);
                }
                lines.add ("%s: %s".printf (name, shown));
            }
            return string.joinv ("\n", lines.data);
        }

        /* Whether two events ask about the same tool with the same input. */
        public bool same_tool (string? other_tool, Json.Object? other_input) {
            if (tool_name != other_tool) {
                return false;
            }
            if ((tool_input == null) != (other_input == null)) {
                return false;
            }
            if (tool_input == null) {
                return true;
            }
            return JsonText.object_compact (tool_input) == JsonText.object_compact ((!) other_input)
                || objects_equal (tool_input, (!) other_input);
        }

        static bool objects_equal (Json.Object a, Json.Object b) {
            var na = new Json.Node (Json.NodeType.OBJECT);
            na.set_object (a);
            var nb = new Json.Node (Json.NodeType.OBJECT);
            nb.set_object (b);
            return JsonText.compact (na, true) == JsonText.compact (nb, true);
        }
    }

    public enum SessionState {
        IDLE,
        WORKING,
        /* Waiting for the user: a permission, or an answer. */
        WAITING,
        DONE;

        public int rank () {
            switch (this) {
            case WAITING: return 3;
            case WORKING: return 2;
            case DONE: return 1;
            default: return 0;
            }
        }
    }

    /* One coding agent session, followed through its hooks. Times are microseconds of the real-time clock. */
    public class AgentSession {
        public string id;
        public string project;
        /* The agent's name when it came through its hooks, shown beside the project. */
        public string? agent;
        public SessionState state = SessionState.IDLE;
        /* What it does, or waits for: a tool summary, a message. */
        public string? detail;
        public int64 since;
        public int64 updated;

        public AgentSession (string id, string project, int64 now) {
            this.id = id;
            this.project = project;
            this.since = now;
            this.updated = now;
        }
    }

    /* Every agent session and what each is doing. */
    public class AgentBoard {
        public HashTable<string, AgentSession> sessions = new HashTable<string, AgentSession> (str_hash, str_equal);

        public void apply (HookEvent event, int64 now) {
            var session = sessions[event.session_id];
            if (session == null) {
                session = new AgentSession (event.session_id, event.project (), now);
            } else if (event.cwd != null || event.agent_name != null) {
                // An event that does not say where it runs (the island's own, after an answer) keeps the project known.
                session.project = event.project ();
            }
            if (event.has_agent) {
                session.agent = event.agent.display_name ();
            }
            var previous = session.state;
            var previous_detail = session.detail;
            switch (event.event_name) {
            case "SessionStart":
                set_state (session, SessionState.IDLE, null);
                break;
            case "UserPromptSubmit":
                // Never the prompt itself: the island can be on a shared screen.
                set_state (session, SessionState.WORKING, null);
                break;
            case "PreToolUse":
            case "PostToolUse":
            case "PostToolUseFailure":
            case "SubagentStart":
                var summary = event.tool_summary ();
                set_state (session, SessionState.WORKING, summary ?? (previous == SessionState.WORKING ? previous_detail : null));
                break;
            case "PermissionRequest":
                set_state (session, SessionState.WAITING, event.request_summary ());
                break;
            case "Notification":
                var type = event.notification_type ?? "";
                if (type == "permission_prompt" || type == "idle_prompt" || type == "agent_needs_input" || type == "elicitation_dialog") {
                    // A permission prompt already shown with its details keeps them.
                    if (previous == SessionState.WAITING && type == "permission_prompt") {
                        break;
                    }
                    set_state (session, SessionState.WAITING, event.message);
                }
                break;
            case "Stop":
                set_state (session, SessionState.DONE, null);
                break;
            case "SessionEnd":
            case "End":
                sessions.remove (event.session_id);
                return;
            // Generic states, from `colctl agent` for agents without hooks.
            case "Working":
                set_state (session, SessionState.WORKING, event.message);
                break;
            case "Waiting":
                set_state (session, SessionState.WAITING, event.message);
                break;
            case "Done":
                set_state (session, SessionState.DONE, null);
                break;
            case "Idle":
                set_state (session, SessionState.IDLE, null);
                break;
            default:
                break;
            }
            if (previous != session.state) {
                session.since = now;
            }
            session.updated = now;
            sessions[event.session_id] = session;
        }

        static void set_state (AgentSession session, SessionState state, string? detail) {
            session.state = state;
            session.detail = detail;
        }

        /* Sessions that finished long enough ago go quiet; those of an agent that never ends them leave. */
        public bool settle (int64 now, double after = 6) {
            bool changed = false;
            var gone = new GenericArray<string> ();
            sessions.foreach ((id, session) => {
                if (session.state == SessionState.DONE && (now - session.updated) >= (int64) (after * 1000000)) {
                    CodingAgent agent;
                    if (CodingAgent.from_name (session.agent, out agent) && !agent.ends_sessions ()) {
                        gone.add (id);
                    } else {
                        session.state = SessionState.IDLE;
                        session.detail = null;
                    }
                    changed = true;
                }
            });
            foreach (var id in gone) {
                sessions.remove (id);
            }
            return changed;
        }

        public bool has_done () {
            bool found = false;
            sessions.foreach ((id, session) => {
                if (session.state == SessionState.DONE) {
                    found = true;
                }
            });
            return found;
        }

        public void forget (string id) {
            sessions.remove (id);
        }

        /* Sessions, the ones that need the user first, then the busy ones, then by recency. */
        public GenericArray<AgentSession> ordered () {
            var list = new GenericArray<AgentSession> ();
            sessions.foreach ((id, session) => list.add (session));
            list.sort ((a, b) => {
                if (a.state.rank () != b.state.rank ()) {
                    return b.state.rank () - a.state.rank ();
                }
                if (a.updated != b.updated) {
                    return a.updated > b.updated ? -1 : 1;
                }
                return strcmp (b.id, a.id);
            });
            return list;
        }

        /* The busiest session, or null when none does anything worth showing. */
        public AgentSession? top (out int active) {
            active = 0;
            AgentSession? first = null;
            foreach (var session in ordered ()) {
                if (session.state == SessionState.IDLE) {
                    continue;
                }
                if (first == null) {
                    first = session;
                }
                active++;
            }
            return first;
        }
    }
}
