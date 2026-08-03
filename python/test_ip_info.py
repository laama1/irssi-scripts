"""
Unit tests for ip_info.py using Python's built-in unittest framework.

How these tests work:
- TestIpInfoMain and TestIpInfoIpv6AndDnsblHelpers are fast unit tests.
- They mock/stub external dependencies so tests are deterministic and do not require network access.
- TestIpInfoLive runs no-mock integration tests by executing ip_info.py as a subprocess.

How to run:
- Run all default tests (live tests are skipped by default):
    python3 -m unittest test_ip_info.py

- Run only live integration tests:
    RUN_LIVE_IP_INFO_TESTS=1 python3 -m unittest test_ip_info.TestIpInfoLive

- Run one specific test method:
    python3 -m unittest test_ip_info.TestIpInfoMain.test_main_with_dnsbl_hits_for_127_0_0_2
"""

import io
import os
import subprocess
import sys
import tempfile
import types
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch


def _install_dns_stub_if_missing():
    if "dns" in sys.modules:
        return

    dns_mod = types.ModuleType("dns")
    resolver_mod = types.ModuleType("dns.resolver")
    reversename_mod = types.ModuleType("dns.reversename")
    exception_mod = types.ModuleType("dns.exception")

    class DummyResolver:
        lifetime = 3.0
        timeout = 3.0

        def resolve(self, *args, **kwargs):
            return []

    resolver_mod.Resolver = DummyResolver
    resolver_mod.NXDOMAIN = type("NXDOMAIN", (Exception,), {})
    resolver_mod.NoAnswer = type("NoAnswer", (Exception,), {})
    resolver_mod.NoNameservers = type("NoNameservers", (Exception,), {})

    reversename_mod.from_address = lambda ip: ip
    exception_mod.Timeout = type("Timeout", (Exception,), {})

    dns_mod.resolver = resolver_mod
    dns_mod.reversename = reversename_mod
    dns_mod.exception = exception_mod

    sys.modules["dns"] = dns_mod
    sys.modules["dns.resolver"] = resolver_mod
    sys.modules["dns.reversename"] = reversename_mod
    sys.modules["dns.exception"] = exception_mod


def _install_geoip2_stub_if_missing():
    if "geoip2" in sys.modules:
        return

    geoip2_mod = types.ModuleType("geoip2")
    database_mod = types.ModuleType("geoip2.database")

    class DummyReader:
        def __init__(self, *args, **kwargs):
            pass

        def city(self, *args, **kwargs):
            return type("CityResp", (), {
                "country": type("Country", (), {"name": None})(),
                "city": type("City", (), {"name": None})(),
            })()

        def asn(self, *args, **kwargs):
            return type("AsnResp", (), {
                "autonomous_system_organization": None,
            })()

        def close(self):
            return None

    database_mod.Reader = DummyReader
    geoip2_mod.database = database_mod

    sys.modules["geoip2"] = geoip2_mod
    sys.modules["geoip2.database"] = database_mod


_install_dns_stub_if_missing()
_install_geoip2_stub_if_missing()

import ip_info


class TestIpInfoMain(unittest.TestCase):
    def setUp(self):
        ip_info.output_buffer.clear()

    def _run_main_for_ip(self, ip):
        def fake_info_output(test_ip):
            if test_ip == "127.0.0.2":
                return [
                    "Country: LO",
                    "City: Loopback",
                    "Region: Loopback",
                    "Org: Local Test",
                    "Hostname: localhost",
                ]
            if test_ip == "1.1.1.1":
                return [
                    "Country: AU",
                    "City: Brisbane",
                    "Region: Queensland",
                    "Org: AS13335 Cloudflare, Inc.",
                    "Hostname: one.one.one.one",
                ]
            return []

        def fake_ping_output(test_ip):
            if test_ip == "127.0.0.2":
                return ["Ping: 0.12 ms"]
            if test_ip == "1.1.1.1":
                return ["Ping: 1.40 ms"]
            return []

        def fake_proxy_check(test_ip):
            if test_ip == "127.0.0.2":
                return ["socks4: 127.0.0.2:4145"]
            return []

        def fake_dnsbl_check(test_ip):
            if test_ip == "127.0.0.2":
                return [
                    "DNSBL dnsbl.dronebl.org: 127.0.0.1",
                    "DNSBL rbl.ircbl.org: 127.0.0.2",
                ]
            if test_ip == "1.1.1.1":
                return []
            return []

        out = io.StringIO()
        with patch.object(ip_info, "use_ipinfo_io", True), \
             patch.object(ip_info, "use_dnsbl", True), \
             patch.object(ip_info, "check_age_of_files", return_value=0), \
             patch.object(ip_info, "download_proxy_lists"), \
             patch.object(ip_info, "format_ipinfo_output", side_effect=fake_info_output), \
             patch.object(ip_info, "format_ping_output", side_effect=fake_ping_output), \
             patch.object(ip_info, "check_if_ip_in_proxy_lists", side_effect=fake_proxy_check), \
             patch.object(ip_info, "check_dnsbl_lists", side_effect=fake_dnsbl_check), \
             patch.object(sys, "argv", ["ip_info.py", ip]), \
             redirect_stdout(out):
            ip_info.output_buffer.clear()
            ip_info.main()

        return out.getvalue().strip()

    def test_main_with_dnsbl_hits_for_127_0_0_2(self):
        line = self._run_main_for_ip("127.0.0.2")
        expected_parts = [
            "Country: LO",
            "City: Loopback",
            "Region: Loopback",
            "Org: Local Test",
            "Hostname: localhost",
            "Ping: 0.12 ms",
            "socks4: 127.0.0.2:4145",
            "DNSBL dnsbl.dronebl.org: 127.0.0.1",
            "DNSBL rbl.ircbl.org: 127.0.0.2",
        ]
        for part in expected_parts:
            self.assertIn(part, line)

    def test_main_with_no_dnsbl_hits_for_1_1_1_1(self):
        line = self._run_main_for_ip("1.1.1.1")
        expected_parts = [
            "Country: AU",
            "City: Brisbane",
            "Region: Queensland",
            "Org: AS13335 Cloudflare, Inc.",
            "Hostname: one.one.one.one",
            "Ping: 1.40 ms",
        ]
        for part in expected_parts:
            self.assertIn(part, line)
        self.assertNotIn("DNSBL ", line)


class TestIpInfoIpv6AndDnsblHelpers(unittest.TestCase):
    def test_normalize_ip_for_dnsbl_maps_ipv4_mapped_ipv6(self):
        parsed = ip_info.normalize_ip_for_dnsbl("::ffff:127.0.0.2")
        self.assertEqual(str(parsed), "127.0.0.2")

    def test_get_dnsbl_reverse_name_ipv4(self):
        parsed = ip_info.normalize_ip_for_dnsbl("1.2.3.4")
        self.assertEqual(ip_info.get_dnsbl_reverse_name(parsed), "4.3.2.1")

    def test_get_dnsbl_reverse_name_ipv6(self):
        parsed = ip_info.normalize_ip_for_dnsbl("2001:db8::1")
        reverse_name = ip_info.get_dnsbl_reverse_name(parsed)
        self.assertTrue(reverse_name.startswith("1.0.0.0"))
        self.assertTrue(reverse_name.endswith("8.b.d.0.1.0.0.2"))

    def test_parse_proxy_list_entry_ipv6_bracket_port(self):
        ip_obj, port = ip_info.parse_proxy_list_entry("[2606:4700:4700::1111]:443")
        self.assertEqual(str(ip_obj), "2606:4700:4700::1111")
        self.assertEqual(port, "443")

    def test_parse_proxy_list_entry_ipv6_no_port(self):
        ip_obj, port = ip_info.parse_proxy_list_entry("2606:4700:4700::1111")
        self.assertEqual(str(ip_obj), "2606:4700:4700::1111")
        self.assertIsNone(port)

    def test_check_if_ip_in_proxy_lists_matches_ipv6_entry(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            proxy_path = os.path.join(tmpdir, "socks4.txt")
            with open(proxy_path, "w", encoding="utf-8") as handle:
                handle.write("[2606:4700:4700::1111]:443\n")

            with patch.object(ip_info, "proxy_file_list", {proxy_path: "test://proxy"}), \
                 patch.object(ip_info, "nmap_given_port", return_value=None):
                matches = ip_info.check_if_ip_in_proxy_lists("2606:4700:4700::1111")

            self.assertEqual(matches, ["socks4: [2606:4700:4700::1111]:443"])

    def test_query_dnsbl_host_collects_a_and_aaaa(self):
        class FakeResolver:
            lifetime = 3.0
            timeout = 3.0

            def resolve(self, query_name, record_type):
                self.last_query = query_name
                if record_type == "A":
                    return ["127.0.0.2"]
                if record_type == "AAAA":
                    return ["::1"]
                return []

        with patch.object(ip_info.dns.resolver, "Resolver", return_value=FakeResolver()):
            matches = ip_info.query_dnsbl_host("2.0.0.127", "dnsbl.example.org")

        self.assertIn("DNSBL dnsbl.example.org A: 127.0.0.2", matches)
        self.assertIn("DNSBL dnsbl.example.org AAAA: ::1", matches)


@unittest.skipUnless(
    os.getenv("RUN_LIVE_IP_INFO_TESTS") == "1",
    "Set RUN_LIVE_IP_INFO_TESTS=1 to run live network integration tests",
)
class TestIpInfoLive(unittest.TestCase):
    script_path = os.path.join(os.path.dirname(__file__), "ip_info.py")
    proxy_filenames = ("socks4.txt", "socks5.txt", "http.txt")

    def _delete_proxy_list_files(self):
        base_dir = os.path.dirname(self.script_path)
        for filename in self.proxy_filenames:
            file_path = os.path.join(base_dir, filename)
            if os.path.exists(file_path):
                os.remove(file_path)

    def _assert_proxy_list_files_exist(self):
        base_dir = os.path.dirname(self.script_path)
        for filename in self.proxy_filenames:
            file_path = os.path.join(base_dir, filename)
            self.assertTrue(
                os.path.exists(file_path),
                msg=f"Expected proxy list file to be recreated: {file_path}",
            )

    def _run_live(self, ip):
        # Force script to exercise proxy list download path before checks.
        self._delete_proxy_list_files()
        completed = subprocess.run(
            [sys.executable, self.script_path, ip],
            capture_output=True,
            text=True,
            timeout=60,
        )
        if "ModuleNotFoundError: No module named 'dns'" in completed.stderr:
            self.skipTest("Live tests require dnspython installed in runtime interpreter")
        self.assertEqual(completed.returncode, 0, msg=completed.stderr)
        self._assert_proxy_list_files_exist()
        line = completed.stdout.strip()
        self.assertNotEqual(line, "")
        return line

    def test_live_127_0_0_2(self):
        line = self._run_live("127.0.0.2")
        self.assertIn("Ping:", line)
        self.assertIn("DNSBL ", line)

    def test_live_1_1_1_1(self):
        line = self._run_live("1.1.1.1")
        # Keep this tolerant for changing external data providers.
        self.assertTrue(
            ("Ping:" in line) or ("Country:" in line) or ("Hostname:" in line),
            msg=f"Unexpected live output: {line}",
        )


if __name__ == "__main__":
    unittest.main()
