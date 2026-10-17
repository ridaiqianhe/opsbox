import json
import pathlib
import subprocess
import unittest


FILTER_PATH = pathlib.Path(__file__).parents[1] / "docker" / "xray-config.jq"


class XrayConfigTests(unittest.TestCase):
    def render(self, *, ipv4_enabled=False, ipv4_udp=True, ipv4_udp_ip=""):
        values = {
            "access": "/var/log/xray/access.log",
            "error": "/var/log/xray/error.log",
            "loglevel": "warning",
            "tag": "socks5-in",
            "listen": "0.0.0.0",
            "username": "test-user",
            "password": "special-#$ password",
            "udp_ip": "",
            "pool": "2001:db8:1234:5678::1200/120",
            "ipv4_listen": "0.0.0.0",
            "ipv4_udp_ip": ipv4_udp_ip,
        }
        command = ["jq", "-n"]
        for name, value in values.items():
            command.extend(["--arg", name, value])
        json_values = {
            "port": 12345,
            "udp": True,
            "ipv4_enabled": ipv4_enabled,
            "ipv4_port": 12346,
            "ipv4_udp": ipv4_udp,
        }
        for name, value in json_values.items():
            command.extend(["--argjson", name, json.dumps(value)])
        command.extend(["-f", str(FILTER_PATH)])
        result = subprocess.run(command, check=True, capture_output=True, text=True)
        return json.loads(result.stdout)

    def test_ipv4_proxy_is_disabled_by_default(self):
        config = self.render()

        self.assertEqual(["socks5-in"], [item["tag"] for item in config["inbounds"]])
        self.assertEqual(["random-ipv6"], [item["tag"] for item in config["outbounds"]])
        self.assertNotIn("routing", config)

    def test_ipv4_proxy_adds_a_routed_listener_and_outbound(self):
        config = self.render(ipv4_enabled=True, ipv4_udp=False, ipv4_udp_ip="198.51.100.8")

        self.assertEqual(
            ["socks5-in", "socks5-ipv4-in"],
            [item["tag"] for item in config["inbounds"]],
        )
        ipv4_inbound = config["inbounds"][1]
        self.assertEqual(12346, ipv4_inbound["port"])
        self.assertFalse(ipv4_inbound["settings"]["udp"])
        self.assertEqual("198.51.100.8", ipv4_inbound["settings"]["ip"])
        self.assertEqual(
            [{"user": "test-user", "pass": "special-#$ password"}],
            ipv4_inbound["settings"]["accounts"],
        )

        ipv4_outbound = config["outbounds"][1]
        self.assertEqual("ipv4-direct", ipv4_outbound["tag"])
        self.assertEqual("0.0.0.0", ipv4_outbound["sendThrough"])
        self.assertEqual("ForceIPv4", ipv4_outbound["settings"]["domainStrategy"])
        self.assertEqual(
            "ForceIPv4",
            ipv4_outbound["streamSettings"]["sockopt"]["domainStrategy"],
        )
        self.assertEqual(
            [{
                "type": "field",
                "inboundTag": ["socks5-ipv4-in"],
                "outboundTag": "ipv4-direct",
            }],
            config["routing"]["rules"],
        )


if __name__ == "__main__":
    unittest.main()
