gtk = dependency('gtk4', version: '>= 4.14')
adw = dependency('libadwaita-1', version: '>= 1.5')
soup = dependency('libsoup-3.0')
pulse = dependency('libpulse')
pulse_glib = dependency('libpulse-mainloop-glib')
gdk_pixbuf = dependency('gdk-pixbuf-2.0')

# gtk4-layer-shell (MIT): the system's when it has one, else built here and linked in, so a package needs nothing more.
# It must come first among the libraries: it stands in for some of libwayland's calls.
layer_shell = dependency('gtk4-layer-shell-0', version: '>= 1.0', required: false)
if not layer_shell.found()
  layer_shell = subproject('gtk4-layer-shell',
    default_options: ['default_library=static', 'introspection=false', 'vapi=false', 'docs=false', 'examples=false', 'tests=false', 'smoke-tests=false'],
  ).get_variable('gtk_layer_shell')
endif

wayland_client = dependency('wayland-client')
gtk_wayland = dependency('gtk4-wayland')
gtk_x11 = dependency('gtk4-x11', required: get_option('x11'))
x11 = dependency('x11', required: get_option('x11'))

scanner = find_program('wayland-scanner')
protocols = []
foreach name : ['wlr-data-control-unstable-v1', 'idle-inhibit-unstable-v1']
  xml = meson.project_source_root() / 'protocols' / name + '.xml'
  protocols += custom_target(name + '-header',
    input: xml, output: name + '-client-protocol.h',
    command: [scanner, 'client-header', '@INPUT@', '@OUTPUT@'])
  protocols += custom_target(name + '-code',
    input: xml, output: name + '-protocol.c',
    command: [scanner, 'private-code', '@INPUT@', '@OUTPUT@'])
endforeach

platform_args = ['-DCOL_HAVE_WAYLAND']
platform_deps = []
if gtk_x11.found() and x11.found()
  platform_args += '-DCOL_HAVE_X11'
  platform_deps += [gtk_x11, x11]
endif

app_sources = files(
  'activities.vala',
  'agent-center.vala',
  'application.vala',
  'compact.vala',
  'control-server.vala',
  'demo.vala',
  'expanded.vala',
  'glyphs.vala',
  'island-view.vala',
  'island-window.vala',
  'live.vala',
  'main.vala',
  'model.vala',
  'mpris.vala',
  'music.vala',
  'network.vala',
  'preferences.vala',
  'settings.vala',
  'style.vala',
  'system.vala',
  'tools.vala',
  'platform.c',
)

app_vapis = [
  valac.find_library('gtk4-layer-shell', dirs: meson.project_source_root() / 'vapi'),  # namespace LayerShell
  valac.find_library('platform', dirs: meson.project_source_root() / 'vapi'),
]

col = executable('col-island', app_sources, protocols,
  dependencies: [layer_shell, core_dep, gtk, adw, soup, pulse, pulse_glib, gdk_pixbuf, gtk_wayland, wayland_client] + platform_deps + app_vapis,
  include_directories: [config_inc, include_directories('.')],
  c_args: ['-include', 'config.h'] + platform_args,
  install: true,
)
