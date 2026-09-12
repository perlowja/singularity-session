project('singularity-session', version: '0.1.0', meson_version: '>= 0.59.0')

install_data(
  'src/singularity-labwc-session',
  'src/singularity-desktop-session',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

install_data(
  'config/labwc/rc.xml',
  'config/labwc/themerc',
  install_dir: get_option('datadir') / 'singularity' / 'labwc',
)

install_data(
  'scripts/migrate-labwc-rc.py',
  install_dir: get_option('datadir') / 'singularity' / 'labwc',
  install_mode: 'rwxr-xr-x',
)

session_test_bash = find_program('bash')
test('session-safe-mode', session_test_bash,
  args: files('tests/session_safe_mode_test.sh'))
