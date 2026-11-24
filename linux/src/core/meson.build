core_sources = files(
  'activity.vala',
  'agents.vala',
  'geometry.vala',
  'hooks.vala',
  'http.vala',
  'intro.vala',
  'json-text.vala',
  'lyrics.vala',
  'paths.vala',
  'request-detail.vala',
)

core_lib = static_library('colcore', core_sources,
  dependencies: core_deps,
  include_directories: config_inc,
  vala_header: 'colcore.h',
  vala_vapi: 'colcore.vapi',
  c_args: ['-include', 'config.h'],
  install: false,
)

core_dep = declare_dependency(
  link_with: core_lib,
  dependencies: core_deps + [cc.find_library('m', required: false)],
  include_directories: [config_inc, include_directories('.')],
)
