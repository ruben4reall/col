foreach name : ['lyrics', 'agents', 'geometry', 'hooks']
  test_exe = executable('test-' + name, 'test-' + name + '.vala',
    dependencies: [core_dep],
    c_args: ['-include', 'config.h'],
  )
  test(name, test_exe, env: ['G_DEBUG=fatal-warnings'])
endforeach

# colctl end to end: a hook never blocks an agent when Col is not running, and answers for it when it is.
test('colctl', find_program('test-colctl.sh'), args: [colctl.full_path()], depends: [colctl])
