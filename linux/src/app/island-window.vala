/* The surface the island lives in. On compositors with wlr-layer-shell (KDE Plasma, COSMIC, Hyprland, Sway, niri,
 * Wayfire): an overlay layer surface anchored to the top edge, centred, never taking the keyboard, that does not push
 * other windows away. Elsewhere (GNOME, which has no layer-shell): an XWayland dock window, kept above the others and
 * placed by hand under the top bar. Either way, the input region follows the island, so clicks pass through the rest. */

namespace Col {
    public class IslandWindow : Gtk.Window {
        public IslandView view;
        Model model;
        public bool layer { get; private set; }
        public bool x11 { get; private set; }

        public signal void surface_replaced ();

        public IslandWindow (Gtk.Application app, Model model) {
            Object (application: app);
            this.model = model;
            title = "Col";
            decorated = false;
            resizable = false;
            add_css_class ("col-island");
            view = new IslandView (model);
            child = view;

            layer = Platform.is_wayland (get_display ()) && LayerShell.is_supported ();
            x11 = !layer && Platform.is_x11 (get_display ());
            if (layer) {
                LayerShell.init_for_window (this);
                LayerShell.set_namespace (this, "col-island");
                LayerShell.set_layer (this, LayerShell.Layer.OVERLAY);
                LayerShell.set_anchor (this, LayerShell.Edge.TOP, true);
                LayerShell.set_anchor (this, LayerShell.Edge.LEFT, false);
                LayerShell.set_anchor (this, LayerShell.Edge.RIGHT, false);
                LayerShell.set_margin (this, LayerShell.Edge.TOP, 0);
                LayerShell.set_keyboard_mode (this, LayerShell.KeyboardMode.NONE);
                apply_layer_settings ();
            } else if (x11) {
                ((Gtk.Widget) this).realize.connect_after (() => {
                    Platform.x11_prepare (this);
                    get_surface ().layout.connect ((w, h) => place_x11 ());
                });
                ((Gtk.Widget) this).map.connect_after (() => place_x11 ());
            }

            set_default_size (view.envelope_width, view.envelope_height);
            view.envelope_changed.connect (() => {
                set_default_size (view.envelope_width, view.envelope_height);
                if (x11) {
                    Idle.add (() => {
                        place_x11 ();
                        return Source.REMOVE;
                    });
                }
            });
            view.input_changed.connect (update_input);
            ((Gtk.Widget) this).realize.connect_after (() => update_input ());
            model.settings.changed.connect ((key) => {
                if (key == "monitor" || key == "below-panels") {
                    if (layer) {
                        apply_layer_settings ();
                    } else if (x11) {
                        place_x11 ();
                    }
                }
            });
            get_display ().get_monitors ().items_changed.connect (() => {
                if (layer) {
                    apply_layer_settings ();
                } else if (x11) {
                    place_x11 ();
                }
            });
        }

        Gdk.Monitor? chosen_monitor () {
            var wanted = model.settings.monitor;
            var monitors = get_display ().get_monitors ();
            Gdk.Monitor? first = null;
            for (uint i = 0; i < monitors.get_n_items (); i++) {
                var monitor = (Gdk.Monitor) monitors.get_item (i);
                if (first == null) {
                    first = monitor;
                }
                if (wanted != "" && monitor.connector == wanted) {
                    return monitor;
                }
            }
            return wanted == "" && layer ? null : first;
        }

        void apply_layer_settings () {
            // -1 floats over panels at the top edge; 0 lets the compositor place the island below them.
            LayerShell.set_exclusive_zone (this, model.settings.below_panels ? 0 : -1);
            LayerShell.set_monitor (this, chosen_monitor ());
        }

        void place_x11 () {
            if (!get_realized ()) {
                return;
            }
            // Not before the window has its size: moved to the top edge empty, GTK takes it for maximized.
            if (get_width () == 0) {
                return;
            }
            var monitor = chosen_monitor ();
            if (monitor == null) {
                return;
            }
            var geometry = monitor.geometry;
            int top = Platform.x11_workarea_top (this);
            if (top < geometry.y || top > geometry.y + geometry.height / 3) {
                top = geometry.y;
            }
            Platform.x11_place (this, geometry.x + geometry.width / 2, top);
        }

        void update_input () {
            var surface = get_surface ();
            if (surface == null) {
                return;
            }
            var rect = view.input_rect ();
            surface.set_input_region (new Cairo.Region.rectangle (rect));
        }
    }
}
