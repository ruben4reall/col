/* JSON written the way people keep their settings files: members in the order they had, text left as it is (no
 * escaped slashes or accents), and numbers as short as they can be while reading back the same. json-glib's own
 * generator writes 0.1 as 0.10000000000000001, which would change a user's file for nothing. */

namespace Col.JsonText {
    public Json.Node? parse (string text) {
        var parser = new Json.Parser ();
        try {
            parser.load_from_data (text, -1);
        } catch (Error e) {
            return null;
        }
        var root = parser.get_root ();
        return root != null ? root.copy () : null;
    }

    public Json.Object? parse_object (string text) {
        var node = parse (text);
        if (node == null || node.get_node_type () != Json.NodeType.OBJECT) {
            return null;
        }
        return node.get_object ();
    }

    /* Pretty, two spaces per level, as Claude Code and Codex write their own files. */
    public string pretty (Json.Node node) {
        var builder = new StringBuilder ();
        write (builder, node, 0, true, false);
        builder.append_c ('\n');
        return builder.str;
    }

    /* On one line, with the members of each object sorted by name: a stable way to show any value. */
    public string compact (Json.Node node, bool sorted = true) {
        var builder = new StringBuilder ();
        write (builder, node, 0, false, sorted);
        return builder.str;
    }

    public string object_compact (Json.Object object) {
        var node = new Json.Node (Json.NodeType.OBJECT);
        node.set_object (object);
        return compact (node, false);
    }

    void newline (StringBuilder builder, int depth) {
        builder.append_c ('\n');
        for (int i = 0; i < depth; i++) {
            builder.append ("  ");
        }
    }

    void write (StringBuilder builder, Json.Node node, int depth, bool pretty, bool sorted) {
        switch (node.get_node_type ()) {
        case Json.NodeType.OBJECT:
            var object = node.get_object ();
            var names = new GenericArray<string> ();
            foreach (unowned string name in object.get_members ()) {
                names.add (name);
            }
            if (sorted) {
                names.sort ((a, b) => strcmp (a, b));
            }
            if (names.length == 0) {
                builder.append ("{}");
                return;
            }
            builder.append_c ('{');
            for (int i = 0; i < names.length; i++) {
                if (i > 0) {
                    builder.append_c (',');
                }
                if (pretty) {
                    newline (builder, depth + 1);
                }
                string_literal (builder, names[i]);
                builder.append (pretty ? ": " : ":");
                write (builder, object.get_member (names[i]), depth + 1, pretty, sorted);
            }
            if (pretty) {
                newline (builder, depth);
            }
            builder.append_c ('}');
            return;
        case Json.NodeType.ARRAY:
            var array = node.get_array ();
            if (array.get_length () == 0) {
                builder.append ("[]");
                return;
            }
            builder.append_c ('[');
            for (uint i = 0; i < array.get_length (); i++) {
                if (i > 0) {
                    builder.append_c (',');
                }
                if (pretty) {
                    newline (builder, depth + 1);
                }
                write (builder, array.get_element (i), depth + 1, pretty, sorted);
            }
            if (pretty) {
                newline (builder, depth);
            }
            builder.append_c (']');
            return;
        case Json.NodeType.NULL:
            builder.append ("null");
            return;
        default:
            break;
        }
        var type = node.get_value_type ();
        if (type == typeof (string)) {
            string_literal (builder, node.get_string ());
        } else if (type == typeof (bool)) {
            builder.append (node.get_boolean () ? "true" : "false");
        } else if (type == typeof (int64)) {
            builder.append (node.get_int ().to_string ());
        } else if (type == typeof (double)) {
            builder.append (number (node.get_double ()));
        } else {
            builder.append ("null");
        }
    }

    /* The shortest text that reads back the same double. */
    public string number (double value) {
        if (value.is_nan () || value.is_infinity () != 0) {
            return "null";
        }
        if (value == Math.floor (value) && Math.fabs (value) < 1e15) {
            return "%.0f".printf (value);
        }
        char[] buffer = new char[double.DTOSTR_BUF_SIZE];
        for (int precision = 15; precision <= 17; precision++) {
            unowned string text = value.format (buffer, "%." + precision.to_string () + "g");
            if (double.parse (text) == value) {
                return text;
            }
        }
        return value.to_string ();
    }

    public void string_literal (StringBuilder builder, string text) {
        builder.append_c ('"');
        unowned uint8[] bytes = text.data;
        for (int i = 0; i < bytes.length; i++) {
            uint8 c = bytes[i];
            switch (c) {
            case '"': builder.append ("\\\""); break;
            case '\\': builder.append ("\\\\"); break;
            case '\n': builder.append ("\\n"); break;
            case '\r': builder.append ("\\r"); break;
            case '\t': builder.append ("\\t"); break;
            case '\b': builder.append ("\\b"); break;
            case '\f': builder.append ("\\f"); break;
            default:
                if (c < 0x20 || c == 0x7f) {
                    builder.append ("\\u%04x".printf (c));
                } else {
                    builder.append_c ((char) c);
                }
                break;
            }
        }
        builder.append_c ('"');
    }

    public string quote (string text) {
        var builder = new StringBuilder ();
        string_literal (builder, text);
        return builder.str;
    }

    /* Small helpers to read what other programs wrote. */
    public string? get_string (Json.Object? object, string name) {
        if (object == null || !object.has_member (name)) {
            return null;
        }
        var node = object.get_member (name);
        if (node.get_node_type () != Json.NodeType.VALUE || node.get_value_type () != typeof (string)) {
            return null;
        }
        return node.get_string ();
    }

    public bool get_double (Json.Object? object, string name, out double value) {
        value = 0;
        if (object == null || !object.has_member (name)) {
            return false;
        }
        var node = object.get_member (name);
        if (node.get_node_type () != Json.NodeType.VALUE) {
            return false;
        }
        var type = node.get_value_type ();
        if (type == typeof (int64)) {
            value = (double) node.get_int ();
            return true;
        }
        if (type == typeof (double)) {
            value = node.get_double ();
            return true;
        }
        return false;
    }

    public bool get_bool (Json.Object? object, string name, bool fallback) {
        if (object == null || !object.has_member (name)) {
            return fallback;
        }
        var node = object.get_member (name);
        if (node.get_node_type () != Json.NodeType.VALUE || node.get_value_type () != typeof (bool)) {
            return fallback;
        }
        return node.get_boolean ();
    }

    public Json.Object? get_object (Json.Object? object, string name) {
        if (object == null || !object.has_member (name)) {
            return null;
        }
        var node = object.get_member (name);
        return node.get_node_type () == Json.NodeType.OBJECT ? node.get_object () : null;
    }

    public Json.Array? get_array (Json.Object? object, string name) {
        if (object == null || !object.has_member (name)) {
            return null;
        }
        var node = object.get_member (name);
        return node.get_node_type () == Json.NodeType.ARRAY ? node.get_array () : null;
    }

    public Json.Node string_node (string text) {
        var node = new Json.Node (Json.NodeType.VALUE);
        node.set_string (text);
        return node;
    }
}
