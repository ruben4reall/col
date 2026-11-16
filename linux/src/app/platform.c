/* What GTK does not offer, written against the protocols' own specifications: a look at the Wayland compositor before
 * GTK starts, the XWayland fallback for desktops without layer-shell, clipboard data control and idle inhibition. */

#include "platform.h"

#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>
#include <glib-unix.h>

#ifdef COL_HAVE_WAYLAND
#include <gdk/wayland/gdkwayland.h>
#include <wayland-client.h>
#include "wlr-data-control-unstable-v1-client-protocol.h"
#include "idle-inhibit-unstable-v1-client-protocol.h"
#endif

#ifdef COL_HAVE_X11
#include <gdk/x11/gdkx.h>
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#endif

/* ---------------------------------------------------------------------------------------------------------------- */
/* Before GTK: does the compositor offer layer-shell? */

#ifdef COL_HAVE_WAYLAND
static void
probe_global (void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version)
{
  if (strcmp (interface, "zwlr_layer_shell_v1") == 0)
    *(gboolean *) data = TRUE;
}

static void
probe_global_remove (void *data, struct wl_registry *registry, uint32_t name)
{
}

static const struct wl_registry_listener probe_listener = { probe_global, probe_global_remove };
#endif

gboolean
col_platform_wayland_has_layer_shell (void)
{
#ifdef COL_HAVE_WAYLAND
  struct wl_display *display = wl_display_connect (NULL);
  if (display == NULL)
    return FALSE;
  gboolean found = FALSE;
  struct wl_registry *registry = wl_display_get_registry (display);
  wl_registry_add_listener (registry, &probe_listener, &found);
  wl_display_roundtrip (display);
  wl_registry_destroy (registry);
  wl_display_disconnect (display);
  return found;
#else
  return FALSE;
#endif
}

gboolean
col_platform_is_wayland (GdkDisplay *display)
{
#ifdef COL_HAVE_WAYLAND
  return GDK_IS_WAYLAND_DISPLAY (display);
#else
  return FALSE;
#endif
}

gboolean
col_platform_is_x11 (GdkDisplay *display)
{
#ifdef COL_HAVE_X11
  return GDK_IS_X11_DISPLAY (display);
#else
  return FALSE;
#endif
}

/* ---------------------------------------------------------------------------------------------------------------- */
/* XWayland fallback (GNOME): a dock window placed by hand. */

#ifdef COL_HAVE_X11
static Atom
atom (Display *display, const char *name)
{
  return XInternAtom (display, name, False);
}

static gboolean
x11_window (GtkWindow *window, Display **display, Window *xid, int *scale)
{
  GdkSurface *surface = gtk_native_get_surface (GTK_NATIVE (window));
  if (surface == NULL || !GDK_IS_X11_SURFACE (surface))
    return FALSE;
  *display = gdk_x11_display_get_xdisplay (gdk_surface_get_display (surface));
  *xid = gdk_x11_surface_get_xid (surface);
  *scale = MAX (1, gdk_surface_get_scale_factor (surface));
  return *xid != 0;
}

#endif

void
col_platform_x11_prepare (GtkWindow *window)
{
#ifdef COL_HAVE_X11
  Display *display;
  Window xid;
  int scale;
  if (!x11_window (window, &display, &xid, &scale))
    return;
  GdkSurface *surface = gtk_native_get_surface (GTK_NATIVE (window));
  gdk_x11_surface_set_skip_taskbar_hint (surface, TRUE);
  gdk_x11_surface_set_skip_pager_hint (surface, TRUE);

  Atom dock = atom (display, "_NET_WM_WINDOW_TYPE_DOCK");
  XChangeProperty (display, xid, atom (display, "_NET_WM_WINDOW_TYPE"), XA_ATOM, 32, PropModeReplace,
                   (unsigned char *) &dock, 1);
  Atom states[] = {
    atom (display, "_NET_WM_STATE_ABOVE"),
    atom (display, "_NET_WM_STATE_STICKY"),
    atom (display, "_NET_WM_STATE_SKIP_TASKBAR"),
    atom (display, "_NET_WM_STATE_SKIP_PAGER"),
  };
  XChangeProperty (display, xid, atom (display, "_NET_WM_STATE"), XA_ATOM, 32, PropModeReplace,
                   (unsigned char *) states, G_N_ELEMENTS (states));
  long every_desktop = 0xFFFFFFFF;
  XChangeProperty (display, xid, atom (display, "_NET_WM_DESKTOP"), XA_CARDINAL, 32, PropModeReplace,
                   (unsigned char *) &every_desktop, 1);
  XFlush (display);
#endif
}

void
col_platform_x11_place (GtkWindow *window, int center_x, int top)
{
#ifdef COL_HAVE_X11
  Display *display;
  Window xid;
  int scale;
  if (!x11_window (window, &display, &xid, &scale))
    return;
  int width = gtk_widget_get_width (GTK_WIDGET (window));
  XMoveWindow (display, xid, (center_x - width / 2) * scale, top * scale);
  XFlush (display);
#endif
}

int
col_platform_x11_workarea_top (GtkWindow *window)
{
#ifdef COL_HAVE_X11
  Display *display;
  Window xid;
  int scale;
  if (!x11_window (window, &display, &xid, &scale))
    return -1;
  Atom type;
  int format;
  unsigned long count, after;
  unsigned char *data = NULL;
  int top = -1;
  if (XGetWindowProperty (display, DefaultRootWindow (display), atom (display, "_NET_WORKAREA"), 0, 4, False,
                          XA_CARDINAL, &type, &format, &count, &after, &data) == Success
      && data != NULL && format == 32 && count >= 4)
    top = (int) ((long *) data)[1] / scale;
  if (data != NULL)
    XFree (data);
  return top;
#else
  return -1;
#endif
}

/* ---------------------------------------------------------------------------------------------------------------- */
/* Wayland globals of ours: data control and idle inhibition, bound once on GDK's own connection. */

#ifdef COL_HAVE_WAYLAND
static struct
{
  gboolean done;
  struct zwlr_data_control_manager_v1 *data_control;
  uint32_t data_control_version;
  struct zwp_idle_inhibit_manager_v1 *idle;
} globals;

static void
globals_add (void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version)
{
  if (strcmp (interface, zwlr_data_control_manager_v1_interface.name) == 0)
    {
      globals.data_control_version = MIN (version, 2);
      globals.data_control = wl_registry_bind (registry, name, &zwlr_data_control_manager_v1_interface,
                                               globals.data_control_version);
    }
  else if (strcmp (interface, zwp_idle_inhibit_manager_v1_interface.name) == 0)
    {
      globals.idle = wl_registry_bind (registry, name, &zwp_idle_inhibit_manager_v1_interface, 1);
    }
}

static void
globals_remove (void *data, struct wl_registry *registry, uint32_t name)
{
}

static const struct wl_registry_listener globals_listener = { globals_add, globals_remove };

/* Binds on a queue of our own, so GDK's events are never dispatched from here, then hands the objects to GDK's queue,
 * which dispatches their events with its own. */
static void
ensure_globals (GdkDisplay *display)
{
  if (globals.done)
    return;
  globals.done = TRUE;
  struct wl_display *wl = gdk_wayland_display_get_wl_display (display);
  struct wl_event_queue *queue = wl_display_create_queue (wl);
  struct wl_display *wrapper = wl_proxy_create_wrapper (wl);
  wl_proxy_set_queue ((struct wl_proxy *) wrapper, queue);
  struct wl_registry *registry = wl_display_get_registry (wrapper);
  wl_proxy_wrapper_destroy (wrapper);
  wl_registry_add_listener (registry, &globals_listener, NULL);
  wl_display_roundtrip_queue (wl, queue);
  if (globals.data_control != NULL)
    wl_proxy_set_queue ((struct wl_proxy *) globals.data_control, NULL);
  if (globals.idle != NULL)
    wl_proxy_set_queue ((struct wl_proxy *) globals.idle, NULL);
  wl_registry_destroy (registry);
  wl_event_queue_destroy (queue);
}

/* ---------------------------------------------------------------------------------------------------------------- */
/* Clipboard data control. */

#define COL_CLIPBOARD_LIMIT (1024 * 1024)

typedef struct
{
  GPtrArray *mimes;
} OfferInfo;

struct _ColDataControl
{
  struct wl_display *display;
  struct zwlr_data_control_device_v1 *device;
  ColClipboardFunc callback;
  gpointer user_data;
  struct zwlr_data_control_offer_v1 *selection;
  /* The copy being read. */
  int read_fd;
  guint read_source;
  GString *buffer;
  /* What we put on the clipboard ourselves. */
  struct zwlr_data_control_source_v1 *source;
  char *source_text;
};

static void
offer_mime (void *data, struct zwlr_data_control_offer_v1 *offer, const char *mime)
{
  OfferInfo *info = data;
  g_ptr_array_add (info->mimes, g_strdup (mime));
}

static const struct zwlr_data_control_offer_v1_listener offer_listener = { offer_mime };

static void
offer_destroy (struct zwlr_data_control_offer_v1 *offer)
{
  if (offer == NULL)
    return;
  OfferInfo *info = zwlr_data_control_offer_v1_get_user_data (offer);
  if (info != NULL)
    {
      g_ptr_array_unref (info->mimes);
      g_free (info);
    }
  zwlr_data_control_offer_v1_destroy (offer);
}

static void
device_data_offer (void *data, struct zwlr_data_control_device_v1 *device, struct zwlr_data_control_offer_v1 *offer)
{
  OfferInfo *info = g_new0 (OfferInfo, 1);
  info->mimes = g_ptr_array_new_with_free_func (g_free);
  zwlr_data_control_offer_v1_add_listener (offer, &offer_listener, info);
}

static void
stop_reading (ColDataControl *control)
{
  if (control->read_source != 0)
    {
      g_source_remove (control->read_source);
      control->read_source = 0;
    }
  if (control->read_fd >= 0)
    {
      close (control->read_fd);
      control->read_fd = -1;
    }
  if (control->buffer != NULL)
    {
      g_string_free (control->buffer, TRUE);
      control->buffer = NULL;
    }
}

static gboolean
on_readable (gint fd, GIOCondition condition, gpointer data)
{
  ColDataControl *control = data;
  char chunk[16384];
  for (;;)
    {
      ssize_t count = read (fd, chunk, sizeof chunk);
      if (count > 0)
        {
          if (control->buffer->len + count > COL_CLIPBOARD_LIMIT)
            {
              /* Too big for a history of text: left out. */
              control->read_source = 0;
              stop_reading (control);
              return G_SOURCE_REMOVE;
            }
          g_string_append_len (control->buffer, chunk, count);
          continue;
        }
      if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
        return G_SOURCE_CONTINUE;
      if (count < 0 && errno == EINTR)
        continue;
      break;
    }
  GString *buffer = control->buffer;
  control->buffer = NULL;
  control->read_source = 0;
  close (control->read_fd);
  control->read_fd = -1;
  if (buffer->len > 0 && g_utf8_validate (buffer->str, buffer->len, NULL))
    control->callback (buffer->str, FALSE, control->user_data);
  g_string_free (buffer, TRUE);
  return G_SOURCE_REMOVE;
}

static gboolean
has_mime (OfferInfo *info, const char *mime)
{
  for (guint i = 0; i < info->mimes->len; i++)
    if (strcmp (g_ptr_array_index (info->mimes, i), mime) == 0)
      return TRUE;
  return FALSE;
}

static void
device_selection (void *data, struct zwlr_data_control_device_v1 *device, struct zwlr_data_control_offer_v1 *offer)
{
  ColDataControl *control = data;
  stop_reading (control);
  if (control->selection != NULL && control->selection != offer)
    offer_destroy (control->selection);
  control->selection = offer;
  if (offer == NULL)
    return;
  OfferInfo *info = zwlr_data_control_offer_v1_get_user_data (offer);
  if (info == NULL)
    return;
  /* Password managers mark the secrets they copy: they never enter the history. */
  if (has_mime (info, "x-kde-passwordManagerHint"))
    {
      control->callback (NULL, TRUE, control->user_data);
      return;
    }
  const char *wanted[] = { "text/plain;charset=utf-8", "UTF8_STRING", "text/plain", "TEXT", "STRING" };
  const char *mime = NULL;
  for (guint i = 0; i < G_N_ELEMENTS (wanted) && mime == NULL; i++)
    if (has_mime (info, wanted[i]))
      mime = wanted[i];
  if (mime == NULL)
    return;
  int fds[2];
  if (pipe2 (fds, O_CLOEXEC) != 0)
    return;
  zwlr_data_control_offer_v1_receive (offer, mime, fds[1]);
  close (fds[1]);
  wl_display_flush (control->display);
  g_unix_set_fd_nonblocking (fds[0], TRUE, NULL);
  control->read_fd = fds[0];
  control->buffer = g_string_new (NULL);
  control->read_source = g_unix_fd_add (fds[0], G_IO_IN | G_IO_HUP | G_IO_ERR, on_readable, control);
}

static void
device_finished (void *data, struct zwlr_data_control_device_v1 *device)
{
  ColDataControl *control = data;
  zwlr_data_control_device_v1_destroy (device);
  control->device = NULL;
}

static void
device_primary_selection (void *data, struct zwlr_data_control_device_v1 *device,
                          struct zwlr_data_control_offer_v1 *offer)
{
  ColDataControl *control = data;
  /* Only the clipboard is kept, not the text merely selected. */
  if (offer != NULL && offer != control->selection)
    offer_destroy (offer);
}

static const struct zwlr_data_control_device_v1_listener device_listener = {
  device_data_offer,
  device_selection,
  device_finished,
  device_primary_selection,
};

ColDataControl *
col_data_control_new (GdkDisplay *display, ColClipboardFunc callback, gpointer user_data)
{
  if (!GDK_IS_WAYLAND_DISPLAY (display))
    return NULL;
  ensure_globals (display);
  if (globals.data_control == NULL)
    return NULL;
  GdkSeat *seat = gdk_display_get_default_seat (display);
  if (seat == NULL)
    return NULL;
  ColDataControl *control = g_new0 (ColDataControl, 1);
  control->display = gdk_wayland_display_get_wl_display (display);
  control->callback = callback;
  control->user_data = user_data;
  control->read_fd = -1;
  control->device = zwlr_data_control_manager_v1_get_data_device (globals.data_control,
                                                                  gdk_wayland_seat_get_wl_seat (seat));
  zwlr_data_control_device_v1_add_listener (control->device, &device_listener, control);
  wl_display_flush (control->display);
  return control;
}

typedef struct
{
  char *text;
  gsize length;
  gsize written;
  int fd;
} Sending;

static gboolean
on_writable (gint fd, GIOCondition condition, gpointer data)
{
  Sending *sending = data;
  while (sending->written < sending->length)
    {
      ssize_t count = write (fd, sending->text + sending->written, sending->length - sending->written);
      if (count > 0)
        {
          sending->written += count;
          continue;
        }
      if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
        return G_SOURCE_CONTINUE;
      if (count < 0 && errno == EINTR)
        continue;
      break;
    }
  close (fd);
  g_free (sending->text);
  g_free (sending);
  return G_SOURCE_REMOVE;
}

static void
source_send (void *data, struct zwlr_data_control_source_v1 *source, const char *mime, int32_t fd)
{
  ColDataControl *control = data;
  if (control->source_text == NULL)
    {
      close (fd);
      return;
    }
  Sending *sending = g_new0 (Sending, 1);
  sending->text = g_strdup (control->source_text);
  sending->length = strlen (sending->text);
  sending->fd = fd;
  g_unix_set_fd_nonblocking (fd, TRUE, NULL);
  g_unix_fd_add (fd, G_IO_OUT | G_IO_ERR | G_IO_HUP, on_writable, sending);
}

static void
source_cancelled (void *data, struct zwlr_data_control_source_v1 *source)
{
  ColDataControl *control = data;
  if (control->source == source)
    {
      control->source = NULL;
      g_clear_pointer (&control->source_text, g_free);
    }
  zwlr_data_control_source_v1_destroy (source);
}

static const struct zwlr_data_control_source_v1_listener source_listener = { source_send, source_cancelled };

void
col_data_control_set_text (ColDataControl *control, const char *text)
{
  if (control == NULL || control->device == NULL || text == NULL)
    return;
  if (control->source != NULL)
    {
      zwlr_data_control_source_v1_destroy (control->source);
      control->source = NULL;
    }
  g_free (control->source_text);
  control->source_text = g_strdup (text);
  control->source = zwlr_data_control_manager_v1_create_data_source (globals.data_control);
  zwlr_data_control_source_v1_add_listener (control->source, &source_listener, control);
  const char *mimes[] = { "text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "TEXT", "STRING" };
  for (guint i = 0; i < G_N_ELEMENTS (mimes); i++)
    zwlr_data_control_source_v1_offer (control->source, mimes[i]);
  zwlr_data_control_device_v1_set_selection (control->device, control->source);
  wl_display_flush (control->display);
}

void
col_data_control_free (ColDataControl *control)
{
  if (control == NULL)
    return;
  stop_reading (control);
  if (control->selection != NULL)
    offer_destroy (control->selection);
  if (control->source != NULL)
    zwlr_data_control_source_v1_destroy (control->source);
  if (control->device != NULL)
    zwlr_data_control_device_v1_destroy (control->device);
  g_free (control->source_text);
  g_free (control);
}

/* ---------------------------------------------------------------------------------------------------------------- */
/* Idle inhibition. */

static struct zwp_idle_inhibitor_v1 *inhibitor;

gboolean
col_idle_inhibit (GtkWindow *window, gboolean inhibit)
{
  GdkDisplay *display = gtk_widget_get_display (GTK_WIDGET (window));
  if (!GDK_IS_WAYLAND_DISPLAY (display))
    return FALSE;
  ensure_globals (display);
  if (globals.idle == NULL)
    return FALSE;
  if (inhibitor != NULL)
    {
      zwp_idle_inhibitor_v1_destroy (inhibitor);
      inhibitor = NULL;
    }
  if (inhibit)
    {
      GdkSurface *surface = gtk_native_get_surface (GTK_NATIVE (window));
      if (surface == NULL || !GDK_IS_WAYLAND_SURFACE (surface))
        return FALSE;
      inhibitor = zwp_idle_inhibit_manager_v1_create_inhibitor (globals.idle, gdk_wayland_surface_get_wl_surface (surface));
    }
  wl_display_flush (gdk_wayland_display_get_wl_display (display));
  return TRUE;
}

#else /* no Wayland */

ColDataControl *
col_data_control_new (GdkDisplay *display, ColClipboardFunc callback, gpointer user_data)
{
  return NULL;
}

void
col_data_control_set_text (ColDataControl *control, const char *text)
{
}

void
col_data_control_free (ColDataControl *control)
{
}

gboolean
col_idle_inhibit (GtkWindow *window, gboolean inhibit)
{
  return FALSE;
}

#endif
