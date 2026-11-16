/* A virtual pointer for the end-to-end checks under a headless Sway, which has no mouse: reads commands on stdin and
 * moves or clicks through wlr-virtual-pointer. The device lives as long as this program, so it keeps reading.
 *
 *   pointer WIDTH HEIGHT
 *   move X Y      absolute position, in the output's logical pixels
 *   click         left button, pressed then released
 *   wait MS
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <linux/input-event-codes.h>
#include <wayland-client.h>
#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

static struct wl_seat *seat;
static struct zwlr_virtual_pointer_manager_v1 *manager;

static void
global (void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version)
{
  if (strcmp (interface, wl_seat_interface.name) == 0 && seat == NULL)
    seat = wl_registry_bind (registry, name, &wl_seat_interface, 1);
  else if (strcmp (interface, zwlr_virtual_pointer_manager_v1_interface.name) == 0)
    manager = wl_registry_bind (registry, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
}

static void
global_remove (void *data, struct wl_registry *registry, uint32_t name)
{
}

static const struct wl_registry_listener listener = { global, global_remove };

static uint32_t
now_ms (void)
{
  struct timespec ts;
  clock_gettime (CLOCK_MONOTONIC, &ts);
  return (uint32_t) (ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

int
main (int argc, char **argv)
{
  if (argc < 3)
    {
      fprintf (stderr, "usage: pointer WIDTH HEIGHT\n");
      return 2;
    }
  uint32_t width = atoi (argv[1]), height = atoi (argv[2]);
  struct wl_display *display = wl_display_connect (NULL);
  if (display == NULL)
    {
      fprintf (stderr, "pointer: no Wayland display\n");
      return 1;
    }
  struct wl_registry *registry = wl_display_get_registry (display);
  wl_registry_add_listener (registry, &listener, NULL);
  wl_display_roundtrip (display);
  if (manager == NULL || seat == NULL)
    {
      fprintf (stderr, "pointer: the compositor has no virtual pointer\n");
      return 1;
    }
  struct zwlr_virtual_pointer_v1 *pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer (manager, seat);
  wl_display_roundtrip (display);

  char line[256];
  while (fgets (line, sizeof line, stdin) != NULL)
    {
      unsigned x, y, ms;
      if (sscanf (line, "move %u %u", &x, &y) == 2)
        {
          zwlr_virtual_pointer_v1_motion_absolute (pointer, now_ms (), x, y, width, height);
          zwlr_virtual_pointer_v1_frame (pointer);
        }
      else if (strncmp (line, "click", 5) == 0)
        {
          zwlr_virtual_pointer_v1_button (pointer, now_ms (), BTN_LEFT, WL_POINTER_BUTTON_STATE_PRESSED);
          zwlr_virtual_pointer_v1_frame (pointer);
          wl_display_roundtrip (display);
          usleep (60000);
          zwlr_virtual_pointer_v1_button (pointer, now_ms (), BTN_LEFT, WL_POINTER_BUTTON_STATE_RELEASED);
          zwlr_virtual_pointer_v1_frame (pointer);
        }
      else if (sscanf (line, "wait %u", &ms) == 1)
        {
          usleep (ms * 1000);
        }
      wl_display_roundtrip (display);
      fprintf (stdout, "ok %s", line);
      fflush (stdout);
    }
  zwlr_virtual_pointer_v1_destroy (pointer);
  wl_display_roundtrip (display);
  wl_display_disconnect (display);
  return 0;
}
