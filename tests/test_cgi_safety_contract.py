"""Regression checks: CGI must be PROVEN before public port 8090 opens.

Static checks do not execute MIPS BusyBox; the on-camera loopback smoke test
must be performed before the new SD firmware is declared hardware verified.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CgiSafetyContract(unittest.TestCase):
    def test_guard_executes_before_public_listener(self):
        init = (ROOT / "rootfs/etc/init.d/S90wificam").read_text()
        self.assertIn("probe_httpd_cgi()", init)
        self.assertIn("if ! probe_httpd_cgi; then", init)
        self.assertLess(init.index("if ! probe_httpd_cgi; then"),
                        init.index('if [ -s "$AUTH_CONF" ]; then'))
        self.assertIn('127.0.0.1:18090', init)
        self.assertIn('{"ok":true,"cgi":"executed"}', init)
        self.assertIn('WIFICAM CGI PRE-FLIGHT FAILED', init)
        self.assertIn('WIFICAM_HTTPD_BIN', init)

    def test_camera_smoke_requires_actual_json_not_http_200_only(self):
        smoke = (ROOT / "scripts/camera_smoke_httpd_cgi.sh").read_text()
        self.assertIn('127.0.0.1:$PORT', smoke)
        self.assertIn('{"ok":true,"cgi":"executed"}', smoke)
        self.assertIn("CGI SOURCE EXPOSED", smoke)
        self.assertIn("trap cleanup EXIT", smoke)
        self.assertNotIn("killall httpd", smoke)

    def test_incremental_builder_never_rebuilds_kernel_or_flashes(self):
        builder = (ROOT / "scripts/rebuild_busybox_cgi_candidate.sh").read_text()
        self.assertIn("br-busybox-rebuild", builder)
        self.assertIn("br-busybox-reconfigure", builder)
        self.assertIn("candidate-busybox", builder)
        self.assertNotIn('make CAMERA="$CAMERA" cleanbuild', builder)
        self.assertNotIn("dd of=/dev/", builder)
        self.assertNotIn("systemctl --user restart", builder)


if __name__ == "__main__":
    unittest.main()
