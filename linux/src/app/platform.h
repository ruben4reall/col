/* What GTK does not offer: a look at the Wayland compositor before GTK starts, the XWayland fallback for desktops
 * without layer-shell, and two Wayland protocols (clipboard data control and idle inhibition). */

#pragma once

#include <gtk/gtk.h>

G_BEGIN_DECLS

/* Whether the Wayland compositor this session runs offers wlr-layer-shell. False without a Wayland session. */
gboolean col_platform_wayland_has_layer_shell (void);

gboolean col_platform_is_wayland (GdkDisplay *display);

/* True when GTK runs on X11 (or XWayland), false on Wayland. */
gboolean col_platform_is_x11 (GdkDisplay *display);

/* XWayland fallback: makes a realized, unmapped window a dock above the others, on every workspace, out of the
 * taskbar and the pager. */
void col_platform_x11_prepare (GtkWindow *window);

/* Puts the window's top centre at (center_x, top), in the monitor's logical pixels. */
void col_platform_x11_place (GtkWindow *window, int center_x, int top);

/* The top of the area windows may use (below a top bar), in logical pixels, or -1 when the window manager does not
 * say. */
int col_platform_x11_workarea_top (GtkWindow *window);

/* Clipboard history on Wayland through wlr-data-control, which a window that never takes focus needs. */
typedef void (*ColClipboardFunc) (const char *text, gboolean secret, gpointer user_data);

typedef struct _ColDataControl ColDataControl;

/* NULL when the compositor does not offer data control. */
ColDataControl *col_data_control_new (GdkDisplay *display, ColClipboardFunc callback, gpointer user_data);
void col_data_control_set_text (ColDataControl *control, const char *text);
void col_data_control_free (ColDataControl *control);

/* Idle inhibition tied to a surface of ours, while it is mapped: keeps the screen awake. */
gboolean col_idle_inhibit (GtkWindow *window, gboolean inhibit);

G_END_DECLS
