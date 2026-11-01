"""Hardware-free checks: private WPA2 credentials never enter public Git artifacts."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

MOD_PATH = Path(__file__).resolve().parents[1] / "scripts/prepare_wifi_overlay.py"
spec = importlib.util.spec_from_file_location("wifi_overlay", MOD_PATH)
assert spec and spec.loader
wifi = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wifi)


class WifiOverlayTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.local = self.root / "wifi.env"
        self.overlay = self.root / "overlay"

    def write(self, content: str, mode: int = 0o600) -> None:
        self.local.write_text(content, encoding="utf-8")
        os.chmod(self.local, mode)

    def test_no_file_means_no_wifi_override(self) -> None:
        self.assertFalse(wifi.prepare(self.local, self.overlay))
        self.assertFalse((self.overlay / "etc/wpa_supplicant.conf").exists())

    def test_wifi_config_uses_pbkdf2_psk_not_plain_password(self) -> None:
        # Well-known PBKDF2/WPA test vector from WPA passphrase specification.
        self.write('WIFI_SSID="IEEE"\nWIFI_PASSWORD="password"\n')
        self.assertTrue(wifi.prepare(self.local, self.overlay))
        path = self.overlay / "etc/wpa_supplicant.conf"
        text = path.read_text()
        self.assertIn("ssid=49454545", text)
        self.assertIn(
            "psk=f42c6fc52df0ebef9ebb4b90b38a5f90"
            "2e83fe1b135a70e23aed762e9710a12e",
            text,
        )
        self.assertNotIn("password", text)
        self.assertNotIn('ssid="', text)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_reject_insecure_permissions(self) -> None:
        self.write('WIFI_SSID="Lab"\nWIFI_PASSWORD="password123"\n',0o644)
        with self.assertRaises(wifi.WifiConfigError):
            wifi.prepare(self.local, self.overlay)

    def test_reject_shell_injection_and_extra_keys(self) -> None:
        self.write('WIFI_SSID="$(touch /tmp/not-allowed)"\nWIFI_PASSWORD="example98765"\n')
        # Is accepted as a *literal* SSID; never executed.
        self.assertTrue(wifi.prepare(self.local, self.overlay))
        self.assertIn("ssid=2428", (self.overlay/"etc/wpa_supplicant.conf").read_text())
        self.write('WIFI_SSID="Lab"\nWIFI_PASSWORD=$(command)\n')
        with self.assertRaises(wifi.WifiConfigError):
            wifi.prepare(self.local, self.overlay)
        self.write('WIFI_SSID="Lab"\nWIFI_PASSWORD="password123"\nSECRET_TOKEN="oops"\n')
        with self.assertRaises(wifi.WifiConfigError):
            wifi.prepare(self.local, self.overlay)

    def test_symlink_is_rejected(self) -> None:
        other = self.root / "other"
        other.write_text('WIFI_SSID="Lab"\nWIFI_PASSWORD="password123"\n')
        self.local.symlink_to(other)
        with self.assertRaises(wifi.WifiConfigError):
            wifi.prepare(self.local, self.overlay)


if __name__ == "__main__":
    unittest.main()
