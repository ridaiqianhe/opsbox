import io
import os
from pathlib import Path
import shlex
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def bash(code, *, env=None, input=None):
    return subprocess.run(
        ["bash", "--noprofile", "--norc", "-c", code],
        input=input, text=True, capture_output=True, timeout=10,
        env={**os.environ, **(env or {})},
    )


class DispatcherTests(unittest.TestCase):
    def test_help_and_eof_do_not_require_root(self):
        for args in (["help"], ["list"], ["version"], []):
            result = subprocess.run(
                ["bash", str(ROOT / "opsbox.sh"), *args],
                input="", text=True, capture_output=True, timeout=5,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("OpsBox", result.stdout)

    def test_dispatch_paths_and_arguments(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = ["vps-proxy/vps-proxy.sh", "random-ipv6-socks/manage.sh", "realm/realm.sh", "ssh/ssh.sh"]
            tools = "snell hysteria2 ss-2022 anytls anytls-reality tuic trojan reality shadow-tls socks-http tcp-tune".split()
            paths += [f"vps-proxy/{tool}.sh" for tool in tools]
            paths += ["system/manage.sh"]
            for name in paths:
                path = root / "modules" / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("printf '%s\\n' " + shlex.quote(name) + " \"$@\"\nexit 7\n")
            for args, expected in [
                (["proxy"], paths[0]), (["ipv6", "status"], paths[1]),
                (["realm"], paths[2]), (["ssh"], paths[3]),
                *[(["proxy", tool, "space value", "--flag"], f"vps-proxy/{tool}.sh") for tool in tools if tool != "tcp-tune"],
                (["proxy", "tcp-tune"], "system/manage.sh"),
            ]:
                result = bash(
                    f"source {shlex.quote(str(ROOT / 'opsbox.sh'))}; "
                    f"OPSBOX_ROOT={shlex.quote(str(root))}; require_root() {{ :; }}; "
                    "dispatch " + shlex.join(args)
                )
                self.assertEqual(result.returncode, 7, result.stderr)
                self.assertEqual(result.stdout.splitlines()[0], expected)
                if "space value" in args:
                    self.assertEqual(result.stdout.splitlines()[1:], ["space value", "--flag"])

    def test_unknown_tools_cannot_escape_module_directory(self):
        for command in ("proxy ../ssh/ssh", "unknown", "proxy '$(touch forbidden)'"):
            result = bash(f"source {shlex.quote(str(ROOT / 'opsbox.sh'))}; dispatch {command}")
            self.assertEqual(result.returncode, 2)


class InstallerTests(unittest.TestCase):
    def test_install_upgrade_preserves_runtime_and_wrapper_paths(self):
        with tempfile.TemporaryDirectory(prefix="opsbox test ") as directory:
            root = Path(directory)
            archive = root / "source.tar.gz"
            with tarfile.open(archive, "w:gz") as output:
                files = {
                    "opsbox-main/opsbox.sh": "printf 'OpsBox installed\\n'\n",
                    "opsbox-main/modules/random-ipv6-socks/manage.sh": "true\n",
                    "opsbox-main/README.md": "test\n",
                }
                for name, content in files.items():
                    info = tarfile.TarInfo(name)
                    info.size = len(content.encode())
                    output.addfile(info, io.BytesIO(content.encode()))
            mockbin = root / "mockbin"
            mockbin.mkdir()
            curl = mockbin / "curl"
            curl.write_text('#!/usr/bin/env bash\ncp "$TEST_ARCHIVE" "${@: -1}"\n')
            curl.chmod(0o755)
            destination = root / "installation with spaces"
            env = {
                "PATH": f"{mockbin}:{os.environ['PATH']}", "TEST_ARCHIVE": str(archive),
                "OPSBOX_DIR": str(destination), "OPSBOX_BIN_DIR": str(root / "bin"),
            }
            result = bash(f"bash {shlex.quote(str(ROOT / 'install.sh'))}", env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            module = destination / "modules/random-ipv6-socks"
            (module / ".env").write_text("existing secret\n")
            (module / "data").mkdir()
            (module / "data/log").write_text("existing log\n")
            result = bash(f"bash {shlex.quote(str(ROOT / 'install.sh'))}", env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((module / ".env").read_text(), "existing secret\n")
            self.assertEqual((module / "data/log").read_text(), "existing log\n")
            launched = subprocess.run([str(root / "bin/opsbox")], text=True, capture_output=True)
            self.assertEqual(launched.stdout, "OpsBox installed\n")

    def test_refuses_unrelated_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            result = bash(
                f"bash {shlex.quote(str(ROOT / 'install.sh'))}",
                env={"OPSBOX_DIR": directory},
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("不是 OpsBox", result.stderr)


class SshTransactionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.config = self.root / "sshd_config"
        self.original = "# original\nPort 22\nPasswordAuthentication no\nInclude /etc/ssh/sshd_config.d/*.conf\nMatch User limited\n    PasswordAuthentication no\n"
        self.config.write_text(self.original)
        self.config.chmod(0o640)
        self.sshd = self.root / "sshd"
        self.sshd.write_text('''#!/usr/bin/env python3
import os, sys
from pathlib import Path
mode, _, filename = sys.argv[1:]
text = Path(filename).read_text()
if mode == '-t':
    sys.exit(1 if os.getenv('INVALID_CANDIDATE') and 'candidate' in filename else 0)
seen = set()
for line in text.splitlines():
    parts = line.split()
    if not parts or parts[0].startswith('#'): continue
    key = parts[0].lower()
    if key == 'match': break
    if key in ('port', 'passwordauthentication', 'permitrootlogin') and key not in seen:
        print(key, parts[1]); seen.add(key)
if os.getenv('EXTRA_PORT'): print('port 2222')
''')
        self.sshd.chmod(0o755)

    def run_setting(self, reload_code=":", extra=None):
        return bash(
            f"source {shlex.quote(str(ROOT / 'modules/ssh/ssh.sh'))}; "
            f"reload_ssh() {{ {reload_code}; }}; apply_setting Port 2200",
            env={"SSHD_CONFIG": str(self.config), "SSHD_BIN": str(self.sshd), **(extra or {})},
        )

    def test_success_preserves_match_include_permissions_and_backup(self):
        result = self.run_setting()
        self.assertEqual(result.returncode, 0, result.stderr)
        updated = self.config.read_text()
        self.assertTrue(updated.startswith("Port 2200\n"))
        self.assertNotIn("Port 22\n", updated)
        self.assertIn("Include /etc/ssh/sshd_config.d/*.conf", updated)
        self.assertIn("Match User limited\n    PasswordAuthentication no", updated)
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o640)
        backups = list(self.root.glob("sshd_config.opsbox-backup.*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), self.original)

    def test_reload_failure_rolls_back(self):
        result = self.run_setting("return 1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.config.read_text(), self.original)

    def test_invalid_candidate_or_include_conflict_leaves_original(self):
        for setting in ("INVALID_CANDIDATE", "EXTRA_PORT"):
            result = self.run_setting(extra={setting: "1"})
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.config.read_text(), self.original)

    def test_password_setting_does_not_change_match_rule(self):
        result = bash(
            f"source {shlex.quote(str(ROOT / 'modules/ssh/ssh.sh'))}; "
            "render_config PasswordAuthentication yes",
            env={"SSHD_CONFIG": str(self.config)},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count("PasswordAuthentication yes"), 1)
        self.assertEqual(result.stdout.count("PasswordAuthentication no"), 1)
        self.assertIn("Match User limited\n    PasswordAuthentication no", result.stdout)


if __name__ == "__main__":
    unittest.main()
