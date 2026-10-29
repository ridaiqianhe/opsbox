import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest
from html.parser import HTMLParser

BASH_MAJOR = int(subprocess.check_output(["bash", "-c", "echo ${BASH_VERSINFO[0]}"], text=True).strip())
ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / 'modules/system/core.sh'
MANAGER = ROOT / 'modules/system/manage.sh'


def run(code, data='', env=None):
    return subprocess.run(
        ['bash', '--noprofile', '--norc', '-c',
         f'source {shlex.quote(str(MANAGER))}; has_tty() {{ return 1; }}; ' + code],
        text=True, input=data, capture_output=True, timeout=10,
        env={**os.environ, **(env or {})},
    )


class ModuleTests(unittest.TestCase):
    def test_import_does_not_run_system_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            log = folder / 'executed'
            for command in ['systemctl', 'nft', 'ip', 'sysctl', 'apt-get', 'mkdir', 'chmod', 'chown', 'rm', 'curl', 'wget']:
                stub = folder / command
                stub.write_text('#!/bin/sh\nprintf "%s\\n" "$0 $*" >> "$COMMAND_LOG"\nexit 99\n')
                stub.chmod(0o755)
            result = run('printf loaded', env={'PATH': f'{folder}:{os.environ["PATH"]}', 'COMMAND_LOG': str(log)})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, 'loaded')
            self.assertFalse(log.exists())

    def test_every_menu_returns_without_mutation(self):
        commands = ['network', 'ipv6-system', 'nat66', 'tcp', 'dns', 'mtu', 'system', 'swap',
                    'cleanup', 'updates', 'security', 'ssh-advanced', 'firewall', 'fail2ban',
                    'site', 'reverse-proxy', 'test', 'cloud', 'recovery']
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            log = folder / 'executed'
            # Read-only probes may fail; any attempted mutation is separately trapped.
            for command in ['systemctl', 'nft', 'sysctl', 'apt-get', 'mkdir', 'chmod', 'chown', 'rm', 'curl', 'wget']:
                stub = folder / command
                stub.write_text('''#!/bin/sh
case "$1" in
  -n|-a|-j|show|status|list|is-active|is-enabled|list-units|list-unit-files|--version) exit 1 ;;
esac
printf '%s\n' "$0 $*" >> "$COMMAND_LOG"
exit 99
''')
                stub.chmod(0o755)
            for command in commands:
                with self.subTest(command=command):
                    result = run(
                        'tcp_fixed_status_text() { echo 未启用; }; tcpfit_status_summary() { echo 未启用; }; '
                        'common_firewall_state_summary() { echo 未启用; }; '
                        f'system_dispatch {command}', '0\n',
                        env={'PATH': f'{folder}:{os.environ["PATH"]}', 'COMMAND_LOG': str(log)},
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn('OpsBox', result.stdout)
            self.assertFalse(log.exists(), log.read_text() if log.exists() else '')

    def test_input_preserves_caller_variable_and_stops_at_eof(self):
        result = run('value=before; read_tty value prompt default; printf "%s" "$value"', 'after\n')
        self.assertEqual(result.stdout, 'after')
        self.assertEqual(result.returncode, 0)
        result = run('read_tty value prompt DELETE; printf should-not-execute')
        self.assertEqual(result.returncode, 0)
        self.assertNotIn('should-not-execute', result.stdout)

    def test_restore_and_migration_require_confirmation(self):
        for choice in ('2', '4'):
            result = run(
                'restore_all() { echo MUTATION; }; secure_site_cleanup_legacy_firewall_on_start() { echo MUTATION; }; '
                'secure_site_migrate_legacy_site() { echo MUTATION; }; restore_menu',
                f'{choice}\nno\n\n0\n',
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('MUTATION', result.stdout)

    def test_no_replacement_characters_or_automatic_main(self):
        text = CORE.read_text()
        self.assertNotIn('\ufffd', text)
        self.assertNotIn('\nmain "$@"', text)
        self.assertNotIn('_legacy_autostop_unused', text)

    def test_existing_ssh_ownership_marker_is_recognized(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / '00-dmitbox.conf'
            original = '# managed by dmitbox.sh\nPasswordAuthentication no\n'
            path.write_text(original)
            result = run(
                'SSH_DROPIN_DIR="$TEST_ROOT"; SSH_DROPIN_FILE="$TEST_ROOT/00-dmitbox.conf"; '
                'SSH_LEGACY_DROPIN_FILE="$TEST_ROOT/99-dmitbox.conf"; '
                'chown() { :; }; chmod() { :; }; ssh_dropin_ensure',
                env={'TEST_ROOT': directory},
            )
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertEqual(path.read_text(), original)

    def test_embedded_python_is_parseable(self):
        text = CORE.read_text()
        scripts = re.findall(r"python3[^\n]*<<'PY'[^\n]*\n(.*?)\nPY\n", text, re.S)
        self.assertGreaterEqual(len(scripts), 8)
        for i, script in enumerate(scripts):
            compile(script, f'embedded-python-{i}', 'exec')

    def test_remote_proxy_rejects_private_and_malformed_addresses(self):
        for address in ['127.0.0.1', '192.168.1.10', '::1', 'fe80::1', 'invalid']:
            result = run(f'reverse_proxy_remote_addresses_safe {shlex.quote(address)}')
            self.assertNotEqual(result.returncode, 0)
        result = run('reverse_proxy_remote_addresses_safe 1.1.1.1 2606:4700:4700::1111')
        self.assertEqual(result.returncode, 0, result.stderr)

    @unittest.skipIf(BASH_MAJOR < 4, "系统模块要求 Bash 4+；Linux CI 执行完整测试")
    def test_proxy_url_parsing_and_command_injection_rejection(self):
        result = run('reverse_proxy_parse_remote_url "https://example.com:8443/api/"; '
                     'printf "%s|%s|%s|%s" "$REVERSE_PROXY_PARSED_SCHEME" "$REVERSE_PROXY_PARSED_HOST" '
                     '"$REVERSE_PROXY_PARSED_PORT" "$REVERSE_PROXY_PARSED_PATH"')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'https|example.com|8443|/api/')
        for url in ['file:///etc/passwd', 'https://user:pass@example.com/', 'https://example.com/$(id)', 'https://example.com/?x=1']:
            result = run('reverse_proxy_parse_remote_url ' + shlex.quote(url))
            self.assertNotEqual(result.returncode, 0, url)

    def test_port_range_validation(self):
        for raw in ['443', '8000-8100']:
            result = run('common_firewall_normalize_port_spec ' + shlex.quote(raw))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), raw)
        for raw in ['0', '65536', '100-10', '22;reboot', '1-65536']:
            self.assertNotEqual(run('common_firewall_normalize_port_spec ' + shlex.quote(raw)).returncode, 0)

    def test_generated_site_and_proxy_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            result = run('SECURE_SITE_ROOT="$TEST_ROOT"; secure_site_generate_homepage example.com',
                         env={'TEST_ROOT': directory})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), '5')
            html = (Path(directory) / 'index.html').read_text()
            parser = HTMLParser()
            parser.feed(html)
            self.assertNotIn('\ufffd', html)
            self.assertNotIn('<script', html.lower())
            self.assertEqual(html.count('class="site"'), 42)
            self.assertIn('https://github.com/', html)
            conf = Path(directory) / 'proxy.conf'
            result = run('secure_site_nginx_ipv6_listen() { :; }; '
                         f'reverse_proxy_write_http_conf example.com {shlex.quote(str(conf))}')
            self.assertEqual(result.returncode, 0, result.stderr)
            data = conf.read_text()
            self.assertIn('server_name example.com;', data)
            self.assertIn('$request_uri', data)
            self.assertIn('limit_except GET HEAD', data)

    def test_nat66_refuses_active_socks_container(self):
        result = run("docker() { echo true; }; have_cmd() { [[ $1 == docker ]]; }; ipv6_rand_apply_nft_runtime")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('SOCKS5', result.stdout + result.stderr)


class NavigationTests(unittest.TestCase):
    def test_main_categories_and_route(self):
        result = subprocess.run(['bash', str(ROOT / 'opsbox.sh')], input='0\n', text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in ['代理与转发', '网络与调优', '系统维护', 'SSH 与安全', '网站与反代', '测试与云主机', '备份与恢复', '高影响操作']:
            self.assertIn(name, result.stdout)
        result = subprocess.run(
            ['bash', '-c', f'source {shlex.quote(str(ROOT / "opsbox.sh"))}; '
             'dispatch() { echo "ROUTE:$1"; }; network_tools_menu'],
            input='5\n0\n', text=True, capture_output=True,
        )
        self.assertIn('ROUTE:tcp', result.stdout)
        self.assertNotIn('ROUTE:proxy', result.stdout)


if __name__ == '__main__':
    unittest.main()
