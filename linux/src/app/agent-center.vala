/* Follows the coding agents that report through their hooks, and holds their permission requests until the user
 * answers from the island. The same rules as the Mac's AgentCenter. */

namespace Col {
    public delegate void Responder (Decision decision);

    public class PendingRequest {
        public string id;
        public string session_id;
        public string project;
        public bool has_agent;
        public CodingAgent agent;
        /* The tool, as people read its name. */
        public string tool;
        /* What it is for, in a line: the command's first line for a shell, never the agent's description of it. */
        public string summary;
        /* What Allow would approve, whole, as the card shows it. */
        public RequestDetail? detail;
        public int64 received;
        public string? tool_name;
        public Json.Object? tool_input;
        public Responder? respond;
        public uint timeout = 0;

        /* Whether the island may allow it: what it approves fits the card, so it was seen whole. A request with input the
         * card does not show is never allowed from it; only one that carries none is. */
        public bool can_allow () {
            if (detail == null) {
                return tool_input == null || tool_input.get_size () == 0;
            }
            return detail.fits_card;
        }
    }

    public class AgentCenter : Object {
        public AgentBoard board = new AgentBoard ();
        /* Requests in the order they came. */
        public GenericArray<PendingRequest> pending = new GenericArray<PendingRequest> ();
        uint settle_source = 0;
        int counter = 0;

        public signal void changed ();
        /* A request arrived: the island opens to show it. */
        public signal void requested ();

        /* How long a permission request waits for the island before falling back to the terminal. */
        public const uint ANSWER_WINDOW = 90;

        public void receive (HookEvent event, owned Responder respond) {
            int64 now = get_real_time ();
            board.apply (event, now);
            // Only agents whose hooks wait for an answer get the buttons; the others show they are waiting for the user.
            if (event.event_name == "PermissionRequest" && (!event.has_agent || event.agent.answers_permissions ())) {
                var request = new PendingRequest ();
                request.id = "%lld-%d".printf (now, ++counter);
                request.session_id = event.session_id;
                request.project = event.project ();
                request.has_agent = event.has_agent;
                request.agent = event.agent;
                request.tool = event.tool_label () ?? "";
                request.summary = event.request_summary () ?? "";
                var detail = event.tool_detail ();
                request.detail = detail != null ? new RequestDetail ((!) detail) : null;
                request.received = now;
                request.tool_name = event.tool_name;
                request.tool_input = event.tool_input;
                request.respond = (owned) respond;
                var id = request.id;
                request.timeout = Timeout.add_seconds (ANSWER_WINDOW, () => {
                    var expired = find (id);
                    if (expired != null) {
                        expired.timeout = 0;
                    }
                    resolve (id, Decision.ASK);
                    changed ();
                    return Source.REMOVE;
                });
                pending.add (request);
                requested ();
            } else {
                respond (Decision.ASK);
                if (event.event_name == "Stop" || event.event_name == "SessionEnd" || event.event_name == "UserPromptSubmit") {
                    // The session moved on: a request it left behind was answered elsewhere.
                    foreach (var request in snapshot ()) {
                        if (request.session_id == event.session_id) {
                            resolve (request.id, Decision.ASK, false);
                        }
                    }
                } else if (event.event_name == "PostToolUse" || event.event_name == "PostToolUseFailure") {
                    // A tool that ran was allowed, in the island or in the terminal: its request, and only its, is over.
                    foreach (var request in snapshot ()) {
                        if (request.session_id == event.session_id && event.same_tool (request.tool_name, request.tool_input)) {
                            resolve (request.id, Decision.ASK, false);
                            break;
                        }
                    }
                }
            }
            schedule_settle ();
            changed ();
        }

        GenericArray<PendingRequest> snapshot () {
            var copy = new GenericArray<PendingRequest> ();
            foreach (var request in pending) {
                copy.add (request);
            }
            return copy;
        }

        PendingRequest? find (string id) {
            foreach (var request in pending) {
                if (request.id == id) {
                    return request;
                }
            }
            return null;
        }

        public void decide (string id, Decision decision) {
            var request = find (id);
            // Allow approves only what the island could show whole; anything longer is answered in the terminal.
            bool allowed = request != null && request.can_allow ();
            resolve (id, decision == Decision.ALLOW && !allowed ? Decision.ASK : decision);
            changed ();
        }

        void resolve (string id, Decision decision, bool update_board = true) {
            var request = find (id);
            if (request == null) {
                return;
            }
            pending.remove (request);
            if (request.timeout != 0) {
                Source.remove (request.timeout);
                request.timeout = 0;
            }
            if (request.respond != null) {
                request.respond (decision);
                request.respond = null;
            }
            if (update_board && decision != Decision.ASK) {
                board.apply (new HookEvent (request.session_id, "PreToolUse"), get_real_time ());
            }
        }

        /* Finished sessions go quiet after a few seconds; one timer for all of them. */
        void schedule_settle () {
            if (settle_source != 0) {
                Source.remove (settle_source);
                settle_source = 0;
            }
            if (!board.has_done ()) {
                return;
            }
            settle_source = Timeout.add (6200, () => {
                settle_source = 0;
                if (board.settle (get_real_time ())) {
                    changed ();
                }
                return Source.REMOVE;
            });
        }

        public PendingRequest? first_request () {
            return pending.length > 0 ? pending[0] : null;
        }
    }

    /* Activities other programs pushed, kept for the Live page. */
    public class CustomActivities : Object {
        public class Entry {
            public ActivityRequest request;
            /* Monotonic microseconds, 0 to keep. */
            public int64 expires;
            public bool finished;
            public int64 updated;
        }

        public GenericArray<Entry> entries = new GenericArray<Entry> ();
        public signal void changed ();

        Entry? find (string id) {
            foreach (var entry in entries) {
                if (entry.request.id == id) {
                    return entry;
                }
            }
            return null;
        }

        public void upsert (ActivityRequest request) {
            int64 now = get_monotonic_time ();
            var entry = find (request.id);
            if (entry == null) {
                entry = new Entry ();
                entries.insert (0, entry);
            }
            entry.request = request;
            entry.expires = request.has_ttl ? now + (int64) (request.ttl * 1000000) : 0;
            entry.finished = false;
            entry.updated = now;
            changed ();
        }

        /* Marks an activity done: it lingers a moment with a check mark, then leaves. */
        public bool finish (string id, string? text) {
            var entry = find (id);
            if (entry == null) {
                return false;
            }
            int64 now = get_monotonic_time ();
            entry.finished = true;
            entry.request.has_progress = false;
            if (text != null) {
                entry.request.text = text;
            }
            entry.expires = now + 3000000;
            entry.updated = now;
            changed ();
            return true;
        }

        public void remove (string id) {
            var entry = find (id);
            if (entry != null) {
                entries.remove (entry);
                changed ();
            }
        }

        public bool prune (int64 now) {
            var gone = new GenericArray<Entry> ();
            foreach (var entry in entries) {
                if (entry.expires != 0 && entry.expires <= now) {
                    gone.add (entry);
                }
            }
            foreach (var entry in gone) {
                entries.remove (entry);
            }
            return gone.length > 0;
        }
    }
}
