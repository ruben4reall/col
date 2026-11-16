/* colctl: pushes live activities to Col, and connects coding agents to it.
 *
 * Talks HTTP over Col's Unix socket ($XDG_RUNTIME_DIR/col/col.sock), so it only reaches the Col of the user running it.
 * The same commands and the same requests as the Mac's colctl. */

namespace Col.Command {
    const string USAGE = """usage: colctl <command> [options]

  push <id> [--title T] [--subtitle S] [--symbol SYMBOL] [--tint COLOR]
            [--progress 0..1 | N%] [--text T] [--priority ambient|standard|alert] [--ttl SECONDS]
                        show or update a live activity in the island
  done <id> [--text T]  mark an activity done: a check mark, then it leaves
  remove <id>           take an activity away
  list                  list the activities pushed by programs
  status                check that Col is running
  settings              open Col's settings

  hooks install [--agent AGENT] [--settings PATH]
                        connect a coding agent to the island; AGENT is claude (default),
                        codex or all
  hooks uninstall [--agent AGENT] [--settings PATH]
  hooks status          show which agents are connected
  hook [--agent AGENT]  the hook itself: reads the agent's event on stdin
  agent <name> <working|waiting|done|idle|end> [--message M] [--session S]
                        report any other agent or script to the island

Colours: white, green, orange, red, blue, purple, yellow, pink, teal, gray, or #RRGGBB.
Example: colctl push build --title Build --symbol hammer --tint orange --progress 40%
""";

    /* How long colctl waits for Col to accept a connection: an agent is never held up by a Col that is not running. */
    const int CONNECT_BUDGET_MS = 300;

    enum Outcome {
        OK,
        NOT_RUNNING,
        FAILED
    }

    [NoReturn]
    void fail (string message) {
        stderr.printf ("colctl: %s\n", message);
        Process.exit (1);
    }

    /* Sends one HTTP request over the socket. */
    Outcome send_request (string method, string path, string? body, int64 response_ms, out int status, out string answer) {
        status = 0;
        answer = "";
        Socket socket;
        try {
            socket = new Socket (SocketFamily.UNIX, SocketType.STREAM, SocketProtocol.DEFAULT);
        } catch (Error e) {
            return Outcome.NOT_RUNNING;
        }
        socket.blocking = false;
        var address = new UnixSocketAddress (Paths.socket_path ());
        try {
            socket.connect (address);
        } catch (IOError.PENDING e) {
            try {
                socket.condition_timed_wait (IOCondition.OUT, CONNECT_BUDGET_MS * 1000);
                socket.check_connect_result ();
            } catch (Error e2) {
                return Outcome.NOT_RUNNING;
            }
        } catch (Error e) {
            return Outcome.NOT_RUNNING;
        }

        int64 deadline = get_monotonic_time () + response_ms * 1000;
        var message = Http.request (method, path, body).data;
        size_t offset = 0;
        try {
            while (offset < message.length) {
                int64 remaining = deadline - get_monotonic_time ();
                if (remaining <= 0) {
                    return Outcome.FAILED;
                }
                socket.condition_timed_wait (IOCondition.OUT, remaining);
                var sent = socket.send (message[offset:message.length]);
                if (sent <= 0) {
                    return Outcome.NOT_RUNNING;
                }
                offset += sent;
            }
            var received = new ByteArray ();
            var chunk = new uint8[16384];
            while (true) {
                int64 remaining = deadline - get_monotonic_time ();
                if (remaining <= 0) {
                    return Outcome.FAILED;
                }
                socket.condition_timed_wait (IOCondition.IN, remaining);
                var count = socket.receive (chunk);
                if (count <= 0) {
                    break;
                }
                received.append (chunk[0:count]);
            }
            socket.close ();
            received.append ({ 0 });
            var text = (string) received.data;
            if (!Http.parse_response (text, out status, out answer)) {
                return Outcome.FAILED;
            }
            return Outcome.OK;
        } catch (Error e) {
            return Outcome.FAILED;
        }
    }

    /* Runs a request a user typed: anything but a success says why and exits. */
    string run (string method, string path, string? body = null) {
        int status;
        string answer;
        switch (send_request (method, path, body, 5000, out status, out answer)) {
        case Outcome.NOT_RUNNING:
            fail ("Col is not running");
        case Outcome.FAILED:
            fail ("no answer from Col");
        default:
            break;
        }
        if (status != 200) {
            var reason = JsonText.get_string (JsonText.parse_object (answer), "error");
            fail (reason ?? "Col answered %d".printf (status));
        }
        return answer;
    }

    HashTable<string, string> options (string[] args, int start) {
        var result = new HashTable<string, string> (str_hash, str_equal);
        for (int i = start; i < args.length; i++) {
            if (!args[i].has_prefix ("--")) {
                fail ("unexpected argument %s".printf (args[i]));
            }
            if (i + 1 >= args.length) {
                fail ("%s needs a value".printf (args[i]));
            }
            result[args[i].substring (2)] = args[i + 1];
            i++;
        }
        return result;
    }

    bool percent_or_fraction (string value, out double fraction) {
        fraction = 0;
        double number;
        if (value.has_suffix ("%")) {
            if (!double.try_parse (value.substring (0, value.length - 1), out number)) {
                return false;
            }
            fraction = number / 100;
            return true;
        }
        if (!double.try_parse (value, out number)) {
            return false;
        }
        fraction = number > 1 ? number / 100 : number;
        return true;
    }

    string read_stdin () {
        var buffer = new ByteArray ();
        var chunk = new uint8[16384];
        while (true) {
            var count = stdin.read (chunk);
            if (count == 0) {
                break;
            }
            buffer.append (chunk[0:count]);
        }
        buffer.append ({ 0 });
        return (string) buffer.data;
    }

    /* Forwards one hook event. Never gets in the agent's way: when Col is not running, or anything goes wrong, it
     * answers what "carry on as usual" means for that agent and exits 0. */
    [NoReturn]
    void hook (CodingAgent agent) {
        var input = read_stdin ();
        var event = JsonText.parse_object (input);
        var name = JsonText.get_string (event, "hook_event_name") ?? "";
        var neutral = agent.neutral_output (name);
        if (event == null || event.get_size () == 0) {
            carry_on (neutral);
        }
        bool waits = agent.answers_permissions () && name == "PermissionRequest";
        int status;
        string answer;
        var outcome = send_request ("POST", "/v1/agents/events?agent=" + agent.id (), input, waits ? 110000 : 3000, out status, out answer);
        if (outcome != Outcome.OK || status != 200 || !waits) {
            carry_on (neutral);
        }
        var decision = JsonText.get_string (JsonText.parse_object (answer), "decision");
        string? output = null;
        if (decision == "allow") {
            output = Decision.ALLOW.hook_output ();
        } else if (decision == "deny") {
            output = Decision.DENY.hook_output ();
        }
        if (output == null) {
            carry_on (neutral);
        }
        stdout.printf ("%s", output);
        stdout.flush ();
        Process.exit (0);
    }

    [NoReturn]
    void carry_on (string? neutral) {
        if (neutral != null) {
            stdout.printf ("%s", neutral);
            stdout.flush ();
        }
        Process.exit (0);
    }

    /* The `col` program beside this one, or on the PATH. */
    string? find_app () {
        var own = Paths.own_executable ();
        if (own != null) {
            var sibling = Path.build_filename (Path.get_dirname (own), "col-island");
            if (FileUtils.test (sibling, FileTest.IS_EXECUTABLE)) {
                return sibling;
            }
        }
        return Environment.find_program_in_path ("col-island");
    }

    int hooks_command (string[] args) {
        var action = args.length > 2 ? args[2] : "";
        var values = options (args, 3);
        var id = values["agent"] ?? "claude";
        if (id != "all" && HookAgent.named (id) == null) {
            fail ("unknown agent %s: claude, codex or all".printf (id));
        }
        var agents = new GenericArray<HookAgent> ();
        foreach (var agent in HookAgent.all ()) {
            if (id == "all" || agent.id () == id) {
                agents.add (agent);
            }
        }
        switch (action) {
        case "install":
        case "uninstall":
            bool failed = false;
            bool install = action == "install";
            foreach (var agent in agents) {
                // With --agent all, only agents present on this machine are connected.
                if (id == "all" && install && !agent.is_present ()) {
                    continue;
                }
                try {
                    stdout.printf ("%s\n", Hooks.edit (agent, agents.length == 1 ? values["settings"] : null, install, Paths.own_executable ()));
                } catch (HooksError e) {
                    stderr.printf ("colctl: %s\n", e.message);
                    failed = true;
                }
            }
            return failed ? 1 : 0;
        case "status":
            foreach (var agent in HookAgent.all ()) {
                var padded = agent.name ();
                while (padded.char_count () < 12) {
                    padded += " ";
                }
                stdout.printf ("%s %s\n", padded, Hooks.is_connected (agent) ? "connected" : "not connected");
            }
            return 0;
        default:
            fail ("hooks takes install, uninstall or status");
        }
    }

    public static int main (string[] args) {
        if (args.length < 2) {
            stdout.printf ("%s", USAGE);
            return 0;
        }
        var command = args[1];
        switch (command) {
        case "push":
            if (args.length < 3 || args[2].has_prefix ("--")) {
                fail ("push needs an id");
            }
            var values = options (args, 3);
            var body = new Json.Object ();
            body.set_string_member ("id", args[2]);
            foreach (unowned string key in new string[] { "title", "subtitle", "symbol", "tint", "text", "priority" }) {
                if (values[key] != null) {
                    body.set_string_member (key, values[key]);
                }
            }
            if (values["progress"] != null) {
                double fraction;
                if (!percent_or_fraction (values["progress"], out fraction)) {
                    fail ("--progress takes 0 to 1, or a percentage");
                }
                body.set_double_member ("progress", fraction);
            }
            if (values["ttl"] != null) {
                double seconds;
                if (!double.try_parse (values["ttl"], out seconds)) {
                    fail ("--ttl takes seconds");
                }
                body.set_double_member ("ttl", seconds);
            }
            run ("POST", "/v1/activities", JsonText.object_compact (body));
            return 0;

        case "done":
            if (args.length < 3) {
                fail ("done needs an id");
            }
            var done_values = options (args, 3);
            var text = done_values["text"];
            var query = text != null ? "?text=" + Uri.escape_string (text, null, false) : "";
            run ("POST", "/v1/activities/%s/done%s".printf (Uri.escape_string (args[2], null, false), query));
            return 0;

        case "remove":
            if (args.length < 3) {
                fail ("remove needs an id");
            }
            run ("DELETE", "/v1/activities/" + Uri.escape_string (args[2], null, false));
            return 0;

        case "list":
            var answer = JsonText.parse_object (run ("GET", "/v1/activities"));
            var list = JsonText.get_array (answer, "activities");
            if (list == null || list.get_length () == 0) {
                stdout.printf ("No activities.\n");
                return 0;
            }
            for (uint i = 0; i < list.get_length (); i++) {
                var item = list.get_object_element (i);
                var parts = new GenericArray<string> ();
                foreach (var part in new string?[] { JsonText.get_string (item, "id"), JsonText.get_string (item, "title") }) {
                    if (part != null && part != "") {
                        parts.add ((!) part);
                    }
                }
                double progress;
                if (JsonText.get_double (item, "progress", out progress)) {
                    parts.add ("%d%%".printf ((int) (progress * 100)));
                } else if (JsonText.get_string (item, "text") != null && JsonText.get_string (item, "text") != "") {
                    parts.add ((!) JsonText.get_string (item, "text"));
                }
                stdout.printf ("%s\n", string.joinv ("  ", parts.data));
            }
            return 0;

        case "status":
            var info = JsonText.parse_object (run ("GET", "/v1/status"));
            double activities = 0, agents = 0;
            JsonText.get_double (info, "activities", out activities);
            JsonText.get_double (info, "agents", out agents);
            stdout.printf ("Col %s is running: %d activities, %d agent sessions.\n",
                JsonText.get_string (info, "version") ?? "", (int) activities, (int) agents);
            return 0;

        case "settings":
            var app = find_app ();
            if (app == null) {
                fail ("Col is not installed");
            }
            try {
                Process.spawn_async (null, { (!) app, "--settings" }, null, SpawnFlags.SEARCH_PATH, null, null);
            } catch (SpawnError e) {
                fail (e.message);
            }
            return 0;

        case "agent":
            if (args.length < 4) {
                fail ("agent needs a name and a state");
            }
            string? state = null;
            switch (args[3].down ()) {
            case "working": state = "Working"; break;
            case "waiting": state = "Waiting"; break;
            case "done": state = "Done"; break;
            case "idle": state = "Idle"; break;
            case "end": state = "End"; break;
            default: fail ("state is working, waiting, done, idle or end");
            }
            // Anything after the options (Codex passes its event as a last argument) is ignored.
            var values = new HashTable<string, string> (str_hash, str_equal);
            int index = 4;
            while (index + 1 < args.length && args[index].has_prefix ("--")) {
                values[args[index].substring (2)] = args[index + 1];
                index += 2;
            }
            var event = new Json.Object ();
            event.set_string_member ("hook_event_name", (!) state);
            event.set_string_member ("agent_name", args[2]);
            event.set_string_member ("session_id", values["session"] ?? args[2].down ());
            if (values["message"] != null) {
                event.set_string_member ("message", values["message"]);
            }
            // Agents call this from their own hooks: never fail loudly when Col is closed.
            int status;
            string answer;
            send_request ("POST", "/v1/agents/events", JsonText.object_compact (event), 3000, out status, out answer);
            return 0;

        case "hook":
            var hook_values = options (args, 2);
            var id = hook_values["agent"] ?? "claude";
            CodingAgent agent;
            // An unknown agent still must not break the agent calling it.
            if (!CodingAgent.parse (id, out agent)) {
                return 0;
            }
            hook (agent);

        case "hooks":
            return hooks_command (args);

        case "help":
        case "--help":
        case "-h":
            stdout.printf ("%s", USAGE);
            return 0;

        case "--version":
        case "version":
            stdout.printf ("colctl %s\n", Config.VERSION);
            return 0;

        default:
            fail ("unknown command %s. Run `colctl help`.".printf (command));
        }
    }
}
