project('daemonette', ['c', 'vala'],
  version : '1.2.0',
  default_options : ['warning_level=3'])

dependencies = [
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('gio-2.0'),
    dependency('gtk+-3.0'),
    dependency('ayatana-appindicator3-0.1'),
    dependency('json-glib-1.0'),
    dependency('gee-0.8'),
    meson.get_compiler('vala').find_library('posix')
]

core_sources = files(
  'src/models/service_definition.vala',
  'src/models/app_settings.vala',
  'src/core/i18n.vala',
  'src/core/log_buffer.vala',
  'src/core/service_manager.vala',
  'src/core/terminal_launcher.vala',
  'src/core/process_runner.vala',
  'src/core/resource_monitor.vala',
  'src/core/ansi_parser.vala',
)

ui_sources = files(
  'src/ui/tray_indicator.vala',
  'src/ui/service_editor_dialog.vala',
  'src/ui/log_viewer_window.vala',
)

sources = core_sources + ui_sources + files('src/main.vala')

exe = executable('daemonette', sources, dependencies : dependencies,
  install : true)

install_data('data/io.github.edpmath.Daemonette.desktop',
  install_dir : get_option('datadir') / 'applications')

install_data('data/io.github.edpmath.Daemonette.metainfo.xml',
  install_dir : get_option('datadir') / 'metainfo')

install_data('data/icons/hicolor/16x16/apps/daemonette.png',
  install_dir : get_option('datadir') / 'icons/hicolor/16x16/apps')
install_data('data/icons/hicolor/24x24/apps/daemonette.png',
  install_dir : get_option('datadir') / 'icons/hicolor/24x24/apps')
install_data('data/icons/hicolor/32x32/apps/daemonette.png',
  install_dir : get_option('datadir') / 'icons/hicolor/32x32/apps')
install_data('data/icons/hicolor/64x64/apps/daemonette.png',
  install_dir : get_option('datadir') / 'icons/hicolor/64x64/apps')
install_data('data/icons/hicolor/128x128/apps/daemonette.png',
  install_dir : get_option('datadir') / 'icons/hicolor/128x128/apps')
install_data('data/icons/hicolor/256x256/apps/daemonette.png',
  install_dir : get_option('datadir') / 'icons/hicolor/256x256/apps')
install_data('data/icons/hicolor/512x512/apps/daemonette.png',
  install_dir : get_option('datadir') / 'icons/hicolor/512x512/apps')

test_sources = core_sources + files(
  'tests/test_utils.vala',
  'tests/test_models.vala',
  'tests/test_i18n.vala',
  'tests/test_log_buffer.vala',
  'tests/test_service_manager.vala',
  'tests/test_process_runner.vala',
  'tests/test_ansi_parser.vala',
  'tests/test_runner.vala',
)

test_exe = executable('daemonette-tests', test_sources,
  dependencies : dependencies)

test('unit-tests', test_exe)
