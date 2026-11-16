desktop_file = files('ch.rubencatalao.Col.desktop')
metainfo_file = files('ch.rubencatalao.Col.metainfo.xml')

install_data(desktop_file, install_dir: datadir / 'applications')
install_data(metainfo_file, install_dir: datadir / 'metainfo')

foreach size : ['16', '24', '32', '48', '64', '128', '256', '512']
  install_data('icons/hicolor' / size + 'x' + size / 'apps' / app_id + '.png',
    install_dir: datadir / 'icons' / 'hicolor' / size + 'x' + size / 'apps')
endforeach

desktop_validate = find_program('desktop-file-validate', required: false)
if desktop_validate.found()
  test('desktop file', desktop_validate, args: [desktop_file])
endif

appstreamcli = find_program('appstreamcli', required: false)
if appstreamcli.found()
  test('metainfo', appstreamcli, args: ['validate', '--no-net', '--pedantic', metainfo_file])
endif
