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
        self.assertIn('WIFICAM CGI PRE-FLIGHT UNAVAILABLE', init)
        self.assertIn('exec httpd "$@"', init)
        self.assertIn('exec busybox httpd "$@"', init)
        self.assertIn('probe_get()', init)
        self.assertIn('grep -qx wget', init)
        self.assertIn('chmod 0755 "$probe_dir"', init)
        self.assertIn('chmod 0755 "$probe_dir/www/cgi-bin/probe"', init)
        self.assertIn('WIFICAM CGI PROBE:', init)

    def test_build_includes_http_client_for_cgi_preflight(self):
        source = (ROOT / "scripts/build_thingino_wificam_image.sh").read_text()
        self.assertIn("CONFIG_WGET=y",source)
        self.assertIn("CONFIG_WGET", source.split('BUSYBOX_REQUIRED_OPTS="', 1)[1].split('"', 1)[0])
        self.assertIn("br-busybox-rebuild",source)
        self.assertIn("BUILD_TARGET=cleanbuild",source)

    def test_helper_edition_disables_stock_voice_and_includes_speech_pcm(self):
        builder = (ROOT / "scripts/build_thingino_wificam_image.sh").read_text()
        packager = (ROOT / "scripts/package_rootfs_overlay.sh").read_text()
        audio = (ROOT / "rootfs/etc/init.d/S94peginelab-audio").read_text()
        self.assertIn("WIFICAM_HELPER_EDITION", builder)
        self.assertIn("BR2_PACKAGE_THINGINO_SOUNDS_STARTUP is not set", builder)
        self.assertIn("boot-voice.s16le", builder)
        self.assertIn("boot-jingle.s16le", builder)
        self.assertIn('WIFICAM_HELPER_EDITION:-0', packager)
        self.assertIn("boot-voice.s16le", packager)
        self.assertIn("if [ -f /etc/wifcam-helper-release ]; then", audio)
        self.assertIn("boot-voice.s16le", audio)
        self.assertIn("boot-jingle.s16le", audio)

    def test_audio_validation_is_edition_specific_in_target_and_sd_rootfs(self):
        # Regression: Helper intentionally removes the original jingle, so
        # neither target nor ext4 validation may demand it unconditionally.
        builder = (ROOT / "scripts/build_thingino_wificam_image.sh").read_text()
        target_start = builder.index('if [ "$WIFICAM_HELPER_EDITION" = 1 ]; then\\n    [ -s "$TARGET/usr/share/wificam-web/assets/boot-voice.s16le"'.replace('\\n', '\\n'))
        target_end = builder.index('\\nfi', target_start)
        target_branch = builder[target_start:target_end]
        self.assertIn('\\nelse\\n', target_branch)
        helper_target, normal_target = target_branch.split('\\nelse\\n', 1)
        self.assertIn('boot-voice.s16le', helper_target)
        self.assertIn('[ ! -e "$TARGET/usr/share/wificam-web/assets/boot-jingle.s16le" ]', helper_target)
        self.assertIn('boot-jingle.s16le', normal_target)
        self.assertIn('boot-jingle.wav', normal_target)
        self.assertIn('224000', normal_target)

        ext_start = builder.index('if [ "$WIFICAM_HELPER_EDITION" = 1 ]; then\\n    debugfs -R')
        ext_end = builder.index('\\nfi', ext_start)
        ext_branch = builder[ext_start:ext_end]
        self.assertIn('\\nelse\\n', ext_branch)
        helper_ext, normal_ext = ext_branch.split('\\nelse\\n', 1)
        self.assertIn('boot-voice.s16le', helper_ext)
        self.assertIn('for old_asset in boot-jingle.s16le boot-jingle.wav', helper_ext)
        self.assertIn('boot-jingle.s16le', normal_ext)
        self.assertIn('boot-jingle.wav', normal_ext)
        self.assertIn("stat /etc/init.d/S94peginelab-audio", builder)

    def test_camera_smoke_requires_actual_json_not_http_200_only(self):
        smoke = (ROOT / "scripts/camera_smoke_httpd_cgi.sh").read_text()
        self.assertIn('127.0.0.1:$PORT', smoke)
        self.assertIn('{"ok":true,"cgi":"executed"}', smoke)
        self.assertIn("CGI SOURCE EXPOSED", smoke)
        self.assertIn("trap cleanup EXIT", smoke)
        self.assertNotIn("killall httpd", smoke)

    def test_builder_sanitizes_ld_library_path_before_buildroot(self):
        builder = (ROOT / "scripts/rebuild_busybox_cgi_candidate.sh").read_text()
        # Regression: Huananzhi shell had an inherited cwd entry in this
        # variable. Buildroot rejects it before compiling BusyBox.
        self.assertIn("unset LD_LIBRARY_PATH", builder)
        self.assertIn("LD_LIBRARY_PATH+x", builder)
        self.assertLess(builder.index("unset LD_LIBRARY_PATH"),
                        builder.index("make CAMERA="))
        self.assertIn("br-busybox-reconfigure", builder)

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
