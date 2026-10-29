import json
import os
from pathlib import Path
import shlex
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'modules/realm/realm.sh'


def realm(code, data='', env=None):
    return subprocess.run(
        ['bash', '--noprofile', '--norc', '-c', f'source {shlex.quote(str(SCRIPT))}; ' + code],
        input=data, text=True, capture_output=True, timeout=10,
        env={**os.environ, **(env or {})},
    )


class RealmTests(unittest.TestCase):
    def test_source_and_help_do_not_modify_system(self):
        result = realm('printf loaded')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'loaded')
        result = subprocess.run(['bash', str(SCRIPT), '--help'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('独立管理脚本', result.stdout)

    def test_directory_selection_preserves_existing_service(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            modern, legacy, unit = root / 'modern', root / 'legacy', root / 'realm.service'
            modern.mkdir(); legacy.mkdir()
            code = 'realm_default_dir ' + shlex.join(map(str, (modern, legacy, unit)))
            self.assertEqual(realm(code).stdout.strip(), str(modern))
            (legacy / 'config.toml').write_text('legacy config')
            self.assertEqual(realm(code).stdout.strip(), str(legacy))
            (modern / 'config.toml').write_text('modern config')
            unit.write_text(f'ExecStart={legacy}/realm -c {legacy}/config.toml\n')
            self.assertEqual(realm(code).stdout.strip(), str(legacy))
            unit.write_text(f'ExecStart={modern}/realm -c {modern}/config.toml\n')
            self.assertEqual(realm(code).stdout.strip(), str(modern))

    def test_architecture_targets(self):
        self.assertIn('x86_64-unknown-linux-musl', realm('realm_asset_targets x86_64').stdout)
        self.assertIn('aarch64-unknown-linux-musl', realm('realm_asset_targets aarch64').stdout)
        self.assertIn('armv7-unknown-linux-musleabihf', realm('realm_asset_targets armv7l').stdout)
        self.assertNotEqual(realm('realm_asset_targets unknown').returncode, 0)

    def test_cancel_uninstall_preserves_program_and_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / 'config.toml').write_text('keep rules')
            result = realm('REALM_DIR="$TEST_DIR"; systemctl() { echo UNEXPECTED; }; uninstall_realm', 'no\n', {'TEST_DIR': directory})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('UNEXPECTED', result.stdout)
            self.assertEqual((path / 'config.toml').read_text(), 'keep rules')

    def test_failed_update_rolls_back_binary_and_preserves_rules(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            installation, package = path / 'installation', path / 'package'
            installation.mkdir(); package.mkdir()
            old = '#!/bin/sh\necho "realm 1.0.0"\n'
            (installation / 'realm').write_text(old)
            (installation / 'realm').chmod(0o755)
            (installation / 'config.toml').write_text('existing rules')
            (package / 'realm').write_text('#!/bin/sh\necho "realm 2.0.0"\n')
            (package / 'realm').chmod(0o755)
            archive = path / 'realm.tar.gz'
            with tarfile.open(archive, 'w:gz') as output:
                output.add(package / 'realm', arcname='realm')
            metadata = path / 'release.json'
            metadata.write_text(json.dumps({'tag_name': 'v2.0.0', 'assets': [{
                'browser_download_url': 'https://github.com/zhboner/realm/releases/download/v2.0.0/realm-x86_64-unknown-linux-musl.tar.gz'
            }]}))
            code = '''
REALM_DIR="$TEST_DIR/installation"
uname() { if [ "$1" = -s ]; then echo Linux; else echo x86_64; fi; }
id() { echo 0; }
realm_download() { if [[ "$1" == */latest ]]; then cp "$TEST_DIR/release.json" "$2"; else cp "$TEST_DIR/realm.tar.gz" "$2"; fi; }
systemctl() { if [ "$1" = is-active ]; then return 0; fi; return 1; }
install_latest_realm
'''
            result = realm(code, env={'TEST_DIR': directory})
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('恢复原版本', result.stdout + result.stderr)
            self.assertEqual((installation / 'realm').read_text(), old)
            self.assertEqual((installation / 'config.toml').read_text(), 'existing rules')


if __name__ == '__main__':
    unittest.main()
