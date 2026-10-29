import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def root_run(code, data='', env=None):
    return subprocess.run(
        ['bash', '--noprofile', '--norc', '-c',
         f'source {shlex.quote(str(ROOT / "opsbox.sh"))}; ' + code],
        input=data, text=True, capture_output=True, timeout=10,
        env={**os.environ, 'TERM': 'dumb', **(env or {})},
    )


def module_run(code, data=''):
    return subprocess.run(
        ['bash', '--noprofile', '--norc', '-c',
         f'source {shlex.quote(str(ROOT / "modules/system/manage.sh"))}; '
         'has_tty() { return 1; }; ' + code],
        input=data, text=True, capture_output=True, timeout=10,
        env={**os.environ, 'TERM': 'dumb'},
    )


class MenuNavigationTests(unittest.TestCase):
    def test_home_overview_is_one_selection_and_one_pause(self):
        result = root_run('dispatch() { printf "EXEC:%s\\n" "$*"; }; main', '1\n\nq\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count('EXEC:overview'), 1)
        self.assertEqual(result.stderr.count('回车继续'), 1)
        self.assertNotIn('按回车返回分类菜单', result.stdout + result.stderr)

    def test_protocol_name_opens_tool_directly_without_extra_pause(self):
        result = root_run('dispatch() { printf "EXEC:%s\\n" "$*"; }; main', 'snell\nq\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('EXEC:proxy snell', result.stdout)
        self.assertNotIn('回车继续', result.stderr)

    def test_home_nine_opens_dd_without_intermediate_category(self):
        result = root_run('run_module() { printf "MODULE:%s\\n" "$*"; return 130; }; main', '9\nq\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count('MODULE:system/manage.sh dd'), 1)
        self.assertIn('DD 重装系统 [高风险]', result.stdout)
        self.assertNotIn('回车继续', result.stderr)

    def test_dd_cancellation_never_reaches_download_or_install(self):
        result = module_run(
            'has_tty() { return 0; }; '
            'read_tty() { IFS= read -r "$1"; }; '
            'read_tty_secret() { IFS= read -r "$1"; }; '
            'ssh_current_ports() { echo 22; }; '
            'have_cmd() { echo MUTATION; return 0; }; '
            'wget() { echo MUTATION; }; '
            'dd_reinstall',
            '2\n22\n2\nexample-password\ncancel\n',
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('已取消', result.stdout)
        self.assertNotIn('MUTATION', result.stdout)

    def test_home_and_quit_propagate_across_category_and_module(self):
        home = root_run('run_module() { echo "MODULE:$*"; return 20; }; main', 'p\n1\nq\n')
        self.assertEqual(home.returncode, 0, home.stderr)
        self.assertIn('MODULE:vps-proxy/snell.sh', home.stdout)
        self.assertEqual(home.stdout.count('快速开始'), 2)
        self.assertNotIn('回车继续', home.stderr)
        quit_result = root_run('run_module() { echo "MODULE:$*"; return 21; }; main', 'p\n1\n3\n')
        self.assertEqual(quit_result.returncode, 0, quit_result.stderr)
        self.assertEqual(quit_result.stdout.count('快速开始'), 1)
        self.assertNotIn('MODULE:system/manage.sh ports', quit_result.stdout)

    def test_system_menu_controls_and_data_input_are_distinct(self):
        for key, expected in [('h', 20), ('q', 21), ('b', 0)]:
            result = module_run('network_menu', key + '\n')
            self.assertEqual(result.returncode, expected, result.stderr)
        # h/q remain ordinary strings in domain/password/confirmation fields.
        result = module_run('read_tty answer "输入域名: " ""; printf "VALUE:%s" "$answer"', 'h\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('VALUE:h', result.stdout)

    def test_search_selects_fixed_catalog_command(self):
        result = root_run('dispatch() { printf "EXEC:%s\\n" "$*"; }; search_menu SNELL', '1\nb\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('EXEC:proxy snell', result.stdout)
        self.assertNotIn('回车继续', result.stderr)

    def test_search_never_evaluates_user_text_or_auto_runs_one_match(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / 'executed'
            query = '$(touch ' + str(marker) + ')'
            result = root_run('search_menu ' + shlex.quote(query), '\n')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(marker.exists())
        result = root_run('dispatch() { echo EXECUTED; }; search_menu snell', 'b\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('EXECUTED', result.stdout)

    def test_recent_tools_are_in_memory_bounded_and_exclude_actions(self):
        result = root_run(
            'dispatch() { :; }; '
            'perform_command snell; perform_command tcp; perform_command snell; '
            'perform_command snapshot; perform_command dd; '
            'printf "RECENT:%s\\n" "${OPSBOX_RECENT[@]}"', '\n\n',
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        recents = [line for line in result.stdout.splitlines() if line.startswith('RECENT:')]
        self.assertEqual(recents, ['RECENT:snell', 'RECENT:tcp'])
        empty = root_run('recent_menu', '\n')
        self.assertEqual(empty.returncode, 0, empty.stderr)
        self.assertIn('还没有使用记录', empty.stdout)

    def test_plain_and_narrow_displays_hide_descriptions(self):
        result = root_run('main', 'q\n', {'COLUMNS': '42', 'NO_COLOR': '1', 'OPSBOX_COLOR': 'always'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('\x1b', result.stdout)
        self.assertNotIn('p 代理与转发   n', result.stdout)
        self.assertNotIn('CPU / 内存 / 磁盘', result.stdout)
        self.assertIn('系统概览', result.stdout)

    def test_command_line_shortcuts_pass_through_to_system_actions(self):
        for command in ['overview', 'check', 'ports', 'cpu', 'memory', 'services', 'port-check']:
            result = root_run('run_module() { printf "%s\\n" "$*"; }; dispatch ' + command)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), 'system/manage.sh ' + command)


if __name__ == '__main__':
    unittest.main()
