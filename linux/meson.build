project('col', ['c', 'vala'],
  version: '3.1.0',
  license: 'MIT',
  meson_version: '>= 1.0',
  default_options: ['warning_level=1', 'buildtype=debugoptimized'],
)

app_id = 'ch.rubencatalao.Col'
gettext_package = 'col'

i18n = import('i18n')
gnome = import('gnome')
cc = meson.get_compiler('c')
valac = meson.get_compiler('vala')

prefix = get_option('prefix')
bindir = prefix / get_option('bindir')
datadir = prefix / get_option('datadir')
localedir = prefix / get_option('localedir')

conf = configuration_data()
conf.set_quoted('VERSION', meson.project_version())
conf.set_quoted('GETTEXT_PACKAGE', gettext_package)
conf.set_quoted('LOCALEDIR', localedir)
conf.set_quoted('APP_ID', app_id)
conf.set_quoted('BINDIR', bindir)
configure_file(output: 'config.h', configuration: conf)
config_inc = include_directories('.')

# Vala writes C that newer compilers warn about; none of it is ours to fix.
add_project_arguments(
  cc.get_supported_arguments([
    '-Wno-unused-variable', '-Wno-unused-but-set-variable', '-Wno-unused-function', '-Wno-unused-label',
    '-Wno-discarded-qualifiers', '-Wno-incompatible-pointer-types', '-Wno-int-conversion',
    '-Wno-error=incompatible-pointer-types', '-Wno-error=int-conversion', '-Wno-error=implicit-function-declaration',
    '-Wno-deprecated-declarations', '-Wno-format-security',
  ]),
  '-DGETTEXT_PACKAGE="' + gettext_package + '"',
  language: 'c',
)
add_project_arguments('--vapidir', meson.current_source_dir() / 'vapi', '--target-glib=2.74', language: 'vala')

glib = dependency('glib-2.0', version: '>= 2.74')
gobject = dependency('gobject-2.0')
gio = dependency('gio-2.0')
gio_unix = dependency('gio-unix-2.0')
json = dependency('json-glib-1.0', version: '>= 1.6')
posix = valac.find_library('posix')
linux_vapi = valac.find_library('linux')
config_vapi = valac.find_library('config', dirs: meson.current_source_dir() / 'vapi')

core_deps = [glib, gobject, gio, gio_unix, json, posix, linux_vapi, config_vapi]

subdir('src/core')
subdir('src/colctl')

if get_option('app')
  subdir('src/app')
  subdir('data')
  subdir('po')
endif

if get_option('tests')
  subdir('tests')
endif
