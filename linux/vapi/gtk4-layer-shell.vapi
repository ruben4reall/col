/* The part of gtk4-layer-shell (MIT) Col uses, declared by hand so the same binding works with the system's library
 * and with the copy meson builds when the system has none. */

[CCode (cheader_filename = "gtk4-layer-shell.h", lower_case_cprefix = "gtk_layer_")]
namespace LayerShell {
    [CCode (cname = "GtkLayerShellLayer", cprefix = "GTK_LAYER_SHELL_LAYER_", has_type_id = false)]
    public enum Layer {
        BACKGROUND,
        BOTTOM,
        TOP,
        OVERLAY
    }

    [CCode (cname = "GtkLayerShellEdge", cprefix = "GTK_LAYER_SHELL_EDGE_", has_type_id = false)]
    public enum Edge {
        LEFT,
        RIGHT,
        TOP,
        BOTTOM
    }

    [CCode (cname = "GtkLayerShellKeyboardMode", cprefix = "GTK_LAYER_SHELL_KEYBOARD_MODE_", has_type_id = false)]
    public enum KeyboardMode {
        NONE,
        EXCLUSIVE,
        ON_DEMAND
    }

    public static bool is_supported ();
    public static void init_for_window (Gtk.Window window);
    public static void set_namespace (Gtk.Window window, string name_space);
    public static void set_layer (Gtk.Window window, Layer layer);
    public static void set_monitor (Gtk.Window window, Gdk.Monitor? monitor);
    public static void set_anchor (Gtk.Window window, Edge edge, bool anchor_to_edge);
    public static void set_margin (Gtk.Window window, Edge edge, int margin_size);
    public static void set_exclusive_zone (Gtk.Window window, int exclusive_zone);
    public static void set_keyboard_mode (Gtk.Window window, KeyboardMode mode);
}
