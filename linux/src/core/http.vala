/* The small HTTP/1.1 Col speaks on its Unix socket, as on the Mac: one request per connection, JSON both ways. */

namespace Col {
    public class HttpRequest {
        public string method = "";
        public string path = "/";
        public HashTable<string, string> query = new HashTable<string, string> (str_hash, str_equal);
        public int content_length = 0;
        public string body = "";

        public const int MAXIMUM_HEAD = 64 * 1024;
        public const int MAXIMUM_BODY = 1 << 20;

        /* Reads the request line and headers, without the blank line that ends them. Null for anything that is not a
         * well-formed request, which is answered 400. */
        public static HttpRequest? parse_head (string head) {
            var lines = head.split ("\r\n");
            if (lines.length == 0) {
                return null;
            }
            var parts = lines[0].split (" ");
            if (parts.length < 2 || parts[0] == "" || parts[1] == "") {
                return null;
            }
            var request = new HttpRequest ();
            request.method = parts[0];
            var target = parts[1];
            int question = target.index_of_char ('?');
            var raw_path = question >= 0 ? target.substring (0, question) : target;
            request.path = Uri.unescape_string (raw_path) ?? raw_path;
            if (question >= 0) {
                foreach (unowned string pair in target.substring (question + 1).split ("&")) {
                    if (pair == "") {
                        continue;
                    }
                    int equals = pair.index_of_char ('=');
                    var name = equals >= 0 ? pair.substring (0, equals) : pair;
                    var value = equals >= 0 ? pair.substring (equals + 1) : "";
                    name = Uri.unescape_string (name.replace ("+", " ")) ?? name;
                    value = Uri.unescape_string (value.replace ("+", " ")) ?? value;
                    request.query[name] = value;
                }
            }
            for (int i = 1; i < lines.length; i++) {
                int colon = lines[i].index_of_char (':');
                if (colon <= 0) {
                    continue;
                }
                var name = lines[i].substring (0, colon).strip ().down ();
                var value = lines[i].substring (colon + 1).strip ();
                if (name == "content-length") {
                    // A length that is not a count of bytes makes the request a bad one.
                    int64 length = 0;
                    if (!int64.try_parse (value, out length) || length < 0 || length > MAXIMUM_BODY) {
                        return null;
                    }
                    request.content_length = (int) length;
                }
            }
            return request;
        }

        /* The path's parts after /v1, or null when it is not under /v1. */
        public string[]? route () {
            var parts = new GenericArray<string> ();
            foreach (unowned string part in path.split ("/")) {
                if (part != "") {
                    parts.add (part);
                }
            }
            if (parts.length == 0 || parts[0] != "v1") {
                return null;
            }
            string[] result = {};
            for (int i = 1; i < parts.length; i++) {
                result += parts[i];
            }
            return result;
        }
    }

    namespace Http {
        public string reason (int status) {
            switch (status) {
            case 200: return "OK";
            case 400: return "Bad Request";
            case 403: return "Forbidden";
            case 404: return "Not Found";
            case 405: return "Method Not Allowed";
            case 503: return "Service Unavailable";
            default: return "Status";
            }
        }

        public string response (int status, string body) {
            return "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s".printf (
                status, reason (status), body.length, body);
        }

        public string error_body (string message) {
            return "{\"error\":%s}".printf (JsonText.quote (message));
        }

        /* A request as colctl sends it. */
        public string request (string method, string path, string? body) {
            var payload = body ?? "";
            return "%s %s HTTP/1.1\r\nHost: col\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s".printf (
                method, path, payload.length, payload);
        }

        /* The status and body of an answer, or false when it is not one. */
        public bool parse_response (string response, out int status, out string body) {
            status = 0;
            body = "";
            int split = response.index_of ("\r\n\r\n");
            if (split < 0) {
                return false;
            }
            var head = response.substring (0, split);
            var parts = head.split (" ");
            int64 code = 0;
            if (parts.length < 2 || !int64.try_parse (parts[1], out code)) {
                return false;
            }
            status = (int) code;
            body = response.substring (split + 4);
            return true;
        }
    }
}
