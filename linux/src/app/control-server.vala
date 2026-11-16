/* The local API: HTTP/1.1 on a Unix socket in $XDG_RUNTIME_DIR/col, readable by this user only (0600 in a 0700 folder),
 * and every connection checked to come from this user. Browsers cannot open Unix sockets, so no web page reaches it.
 * The same routes and JSON as the Mac (docs/api.md):
 *
 *     GET    /v1/status
 *     GET    /v1/activities
 *     POST   /v1/activities                 body: an activity
 *     POST   /v1/activities/<id>/done       ?text=Done
 *     DELETE /v1/activities/<id>
 *     POST   /v1/agents/events?agent=codex  body: a hook event as the agent wrote it; answers {"decision": ...}
 */

namespace Col {
    public delegate void Respond (int status, string body);

    public class ControlServer : Object {
        SocketService? service;
        string path;
        Model model;

        public ControlServer (Model model) {
            this.model = model;
            this.path = Paths.socket_path ();
        }

        /* Whether a Col already listens there. A file left by a Col that quit refuses the connection. */
        static bool is_answered (string path) {
            try {
                var client = new SocketClient ();
                client.timeout = 1;
                var connection = client.connect (new UnixSocketAddress (path), null);
                connection.close ();
                return true;
            } catch (Error e) {
                return false;
            }
        }

        public void start () throws Error {
            var folder = Path.get_dirname (path);
            DirUtils.create_with_parents (folder, 0700);
            if (is_answered (path)) {
                throw new IOError.ADDRESS_IN_USE ("another Col listens on %s", path);
            }
            FileUtils.unlink (path);
            service = new SocketService ();
            service.add_address (new UnixSocketAddress (path), SocketType.STREAM, SocketProtocol.DEFAULT, null, null);
            FileUtils.chmod (path, 0600);
            service.incoming.connect ((connection, source) => {
                serve.begin (connection);
                return true;
            });
            service.start ();
        }

        public void stop () {
            if (service != null) {
                service.stop ();
                service.close ();
                service = null;
                FileUtils.unlink (path);
            }
        }

        async void serve (SocketConnection connection) {
            // Only processes running as this user: the socket's mode says so, and the peer's credentials confirm it.
            try {
                var credentials = connection.get_socket ().get_credentials ();
                if (credentials.get_unix_user () != Posix.getuid ()) {
                    yield write (connection, 403, Http.error_body ("forbidden"));
                    return;
                }
            } catch (Error e) {
                yield write (connection, 403, Http.error_body ("forbidden"));
                return;
            }
            var cancellable = new Cancellable ();
            // A client that sends nothing is let go after five seconds.
            uint timeout = Timeout.add_seconds (5, () => {
                cancellable.cancel ();
                return Source.REMOVE;
            });
            HttpRequest? request = null;
            try {
                var input = new DataInputStream (connection.input_stream);
                input.newline_type = DataStreamNewlineType.CR_LF;
                var head = new StringBuilder ();
                while (true) {
                    size_t length;
                    var line = yield input.read_line_async (Priority.DEFAULT, cancellable, out length);
                    if (line == null) {
                        break;
                    }
                    if (line == "") {
                        request = HttpRequest.parse_head (head.str);
                        break;
                    }
                    head.append (line);
                    head.append ("\r\n");
                    if (head.len > HttpRequest.MAXIMUM_HEAD) {
                        break;
                    }
                }
                if (request != null && request.content_length > 0) {
                    var body = new uint8[request.content_length + 1];
                    size_t read;
                    yield input.read_all_async (body[0:request.content_length], Priority.DEFAULT, cancellable, out read);
                    if (read != request.content_length) {
                        request = null;
                    } else {
                        body[request.content_length] = 0;
                        request.body = ((string) body).dup ();
                    }
                }
            } catch (Error e) {
                request = null;
            }
            if (timeout != 0 && !cancellable.is_cancelled ()) {
                Source.remove (timeout);
            }
            if (request == null) {
                yield write (connection, 400, Http.error_body ("bad request"));
                return;
            }
            var done = false;
            route ((!) request, (status, body) => {
                if (done) {
                    return;
                }
                done = true;
                write.begin (connection, status, body);
            });
        }

        async void write (SocketConnection connection, int status, string body) {
            try {
                size_t written;
                yield connection.output_stream.write_all_async (Http.response (status, body).data, Priority.DEFAULT, null, out written);
                yield connection.close_async ();
            } catch (Error e) {
            }
        }

        void route (HttpRequest request, owned Respond respond) {
            var parts = request.route ();
            if (parts == null) {
                respond (404, Http.error_body ("not found"));
                return;
            }
            var route = (!) parts;
            var id = route.length >= 2 && route[0] == "activities" ? route[1] : "";
            if (request.method == "GET" && route.length == 1 && route[0] == "status") {
                respond (200, "{\"activities\":%d,\"agents\":%u,\"app\":\"Col\",\"version\":%s}".printf (
                    model.custom.entries.length, model.agents.board.sessions.size (), JsonText.quote (Config.VERSION)));
            } else if (request.method == "GET" && route.length == 1 && route[0] == "activities") {
                var list = new Json.Array ();
                foreach (var entry in model.custom.entries) {
                    var item = new Json.Object ();
                    item.set_boolean_member ("finished", entry.finished);
                    item.set_string_member ("id", entry.request.id);
                    if (entry.request.has_progress) {
                        item.set_double_member ("progress", entry.request.progress);
                    }
                    if (entry.request.text != null) {
                        item.set_string_member ("text", entry.request.text);
                    }
                    if (entry.request.title != null) {
                        item.set_string_member ("title", entry.request.title);
                    }
                    list.add_object_element (item);
                }
                var answer = new Json.Object ();
                answer.set_array_member ("activities", list);
                respond (200, JsonText.object_compact (answer));
            } else if (request.method == "POST" && route.length == 1 && route[0] == "activities") {
                var object = JsonText.parse_object (request.body);
                try {
                    if (object == null) {
                        throw new ActivityError.INVALID ("expected an activity with an id");
                    }
                    var activity = ActivityRequest.from_json ((!) object);
                    model.custom.upsert (activity);
                    respond (200, "{\"id\":%s}".printf (JsonText.quote (activity.id)));
                } catch (ActivityError e) {
                    respond (400, Http.error_body ("expected an activity with an id"));
                }
            } else if (request.method == "POST" && route.length == 3 && route[0] == "activities" && route[2] == "done" && id != "") {
                if (!model.custom.finish (id, request.query["text"])) {
                    respond (404, Http.error_body ("no such activity"));
                    return;
                }
                respond (200, "{\"id\":%s}".printf (JsonText.quote (id)));
            } else if (request.method == "DELETE" && route.length == 2 && route[0] == "activities" && id != "") {
                model.custom.remove (id);
                respond (200, "{\"id\":%s}".printf (JsonText.quote (id)));
            } else if (request.method == "POST" && route.length == 2 && route[0] == "agents" && route[1] == "events") {
                CodingAgent agent;
                var raw = JsonText.parse_object (request.body);
                if (!CodingAgent.parse (request.query["agent"] ?? "claude", out agent) || raw == null) {
                    respond (400, Http.error_body ("expected a hook event"));
                    return;
                }
                var event = agent.event_from ((!) raw);
                // Events an agent sends that Col does not follow are simply acknowledged.
                if (event == null) {
                    respond (200, "{\"decision\":\"ask\"}");
                    return;
                }
                model.agents.receive ((!) event, (decision) => {
                    respond (200, "{\"decision\":\"%s\"}".printf (decision.to_key ()));
                });
            } else {
                respond (404, Http.error_body ("not found"));
            }
        }

        /* col://push?id=build&title=Build&progress=0.4, col://done?id=build, col://remove?id=build, col://settings. */
        public static bool open_link (Model model, string link) {
            Uri uri;
            try {
                uri = Uri.parse (link, UriFlags.NONE);
            } catch (UriError e) {
                return false;
            }
            if (uri.get_scheme () != "col" && uri.get_scheme () != "islet") {
                return false;
            }
            var action = uri.get_host () ?? "";
            var query = new HashTable<string, string> (str_hash, str_equal);
            if (uri.get_query () != null) {
                try {
                    query = Uri.parse_params ((!) uri.get_query (), -1, "&", UriParamsFlags.NONE);
                } catch (UriError e) {
                }
            }
            if (action == "settings" || action == "welcome") {
                model.settings_requested ();
                return true;
            }
            var id = query["id"];
            if (id == null || id == "") {
                return false;
            }
            switch (action) {
            case "push":
                var request = new ActivityRequest ((!) id);
                request.title = query["title"];
                request.subtitle = query["subtitle"];
                request.symbol = query["symbol"];
                request.tint = query["tint"];
                request.text = query["text"];
                request.priority = query["priority"];
                double value = 0;
                if (query["progress"] != null && double.try_parse (query["progress"], out value)) {
                    request.has_progress = true;
                    request.progress = value;
                }
                if (query["ttl"] != null && double.try_parse (query["ttl"], out value)) {
                    request.has_ttl = true;
                    request.ttl = value;
                }
                try {
                    model.custom.upsert (request.validated ());
                } catch (ActivityError e) {
                    return false;
                }
                return true;
            case "done":
                return model.custom.finish ((!) id, query["text"]);
            case "remove":
                model.custom.remove ((!) id);
                return true;
            default:
                return false;
            }
        }
    }
}
