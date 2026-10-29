import contextlib
import importlib.util
import io
import ipaddress
import json
import pathlib
import sys
import unittest
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).parents[1] / "docker" / "select_pool.py"
SPEC = importlib.util.spec_from_file_location("select_pool", MODULE_PATH)
select_pool = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(select_pool)


def address_data():
    return json.dumps(
        [
            {
                "addr_info": [
                    {
                        "family": "inet6",
                        "local": "2001:db8:1234:5678::abcd",
                        "prefixlen": 64,
                        "scope": "global",
                        "temporary": True,
                    },
                    {
                        "family": "inet6",
                        "local": "2001:db8:1234:5678::1",
                        "prefixlen": 64,
                        "scope": "global",
                    },
                    {
                        "family": "inet6",
                        "local": "2001:db8:1234:5678::2",
                        "prefixlen": 64,
                        "scope": "global",
                        "tentative": True,
                    },
                ]
            }
        ]
    )


class SelectPoolTests(unittest.TestCase):
    def run_main(self, *arguments):
        stdout = io.StringIO()
        stderr = io.StringIO()
        argv = [str(MODULE_PATH), "--interface", "eth0", *arguments]
        with mock.patch.object(sys, "argv", argv), mock.patch.object(
            select_pool.subprocess, "check_output", return_value=address_data()
        ), contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            try:
                select_pool.main()
                exit_code = 0
            except SystemExit as exc:
                exit_code = exc.code
        return exit_code, stdout.getvalue().strip(), stderr.getvalue().strip()

    @mock.patch.object(select_pool.subprocess, "check_output", return_value=address_data())
    def test_stable_address_is_preferred_and_tentative_is_ignored(self, _):
        candidates = select_pool.global_networks("eth0")
        self.assertEqual(ipaddress.IPv6Address("2001:db8:1234:5678::1"), candidates[0][0])
        self.assertEqual(2, len(candidates))

    def test_automatic_pool_is_stable_and_inside_parent_prefix(self):
        first = self.run_main("--prefix-len", "120", "--seed", "ci-seed")
        second = self.run_main("--prefix-len", "120", "--seed", "ci-seed")
        self.assertEqual(0, first[0])
        self.assertEqual(first[1], second[1])
        pool = ipaddress.ip_network(first[1])
        self.assertEqual(120, pool.prefixlen)
        self.assertTrue(pool.subnet_of(ipaddress.ip_network("2001:db8:1234:5678::/64")))

    def test_explicit_pool_is_accepted(self):
        result = self.run_main("--pool", "2001:db8:1234:5678::1200/120")
        self.assertEqual((0, "2001:db8:1234:5678::1200/120", ""), result)

    def test_broad_pool_is_rejected_by_default(self):
        result = self.run_main("--pool", "2001:db8:1234:5678::/64")
        self.assertEqual(1, result[0])
        self.assertIn("refusing broad pool", result[2])

    def test_pool_outside_interface_prefix_is_rejected(self):
        result = self.run_main("--pool", "2001:db8:ffff::/120")
        self.assertEqual(1, result[0])
        self.assertIn("is not inside a global prefix", result[2])


if __name__ == "__main__":
    unittest.main()

