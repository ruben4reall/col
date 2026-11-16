[CCode (cheader_filename = "platform.h", lower_case_cprefix = "col_platform_")]
namespace Platform {
    public bool wayland_has_layer_shell ();
    public bool is_wayland (Gdk.Display display);
    public bool is_x11 (Gdk.Display display);
    public void x11_prepare (Gtk.Window window);
    public void x11_place (Gtk.Window window, int center_x, int top);
    public int x11_workarea_top (Gtk.Window window);

    [CCode (cname = "col_idle_inhibit")]
    public bool idle_inhibit (Gtk.Window window, bool inhibit);

    [CCode (cname = "ColClipboardFunc", has_target = true)]
    public delegate void ClipboardFunc (string? text, bool secret);

    [Compact, CCode (cname = "ColDataControl", free_function = "col_data_control_free")]
    public class DataControl {
        [CCode (cname = "col_data_control_new")]
        public static DataControl? create (Gdk.Display display, ClipboardFunc callback);
        [CCode (cname = "col_data_control_set_text")]
        public void set_text (string text);
    }
}
