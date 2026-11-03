"""Static contract for the pinned Galayou G2 T23N lean build.

GitHub CI cannot boot the MIPS camera; these guard the exact configuration.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
BUILDER = (ROOT / "scripts/build_thingino_wificam_image.sh").read_text()


class T23NLeanProfile(unittest.TestCase):
    def test_camera_specific_peripherals_survive_optimization(self):
        for required in (
            'BR2_INGENIC_SOC_MODEL="t23n"',
            'BR2_SENSOR_1_NAME="sc2336"',
            'BR2_PACKAGE_WIFI_ATBM6012BX=y',
            'BR2_PACKAGE_THINGINO_KOPT_DWC2=y',
            'BR2_PACKAGE_THINGINO_KOPT_DWC2_WIFI_ONLY=y',
            'BR2_PACKAGE_THINGINO_KOPT_MMC0_1BIT=y',
            'BR2_THINGINO_SDCARD=y',
            'BR2_THINGINO_MOTORS=y',
            'BR2_THINGINO_AUDIO=y',
        ):
            self.assertIn(required, BUILDER)

    def test_lean_raptor_retains_camera_and_recording(self):
        for daemon in ("RVD", "RSD", "RAD", "RHD", "ROD", "RIC", "RMR", "RMD"):
            self.assertIn(f'BR2_PACKAGE_THINGINO_RAPTOR_{daemon}=y', BUILDER)
        for daemon in ("FULL", "WEBRTC", "WEBTORRENT", "RSP", "RSR", "RWC", "RFS", "RSD555"):
            self.assertIn(f'# BR2_PACKAGE_THINGINO_RAPTOR_{daemon} is not set', BUILDER)
        self.assertIn('unneeded Raptor feature enabled', BUILDER)

    def test_safe_candidates_and_cgi_still_required(self):
        self.assertIn('IMAGE_DIR="$REPO_DIR/out/candidate-sd"', BUILDER)
        self.assertIn('IMAGE_DIR="$REPO_DIR/out/private-sd"', BUILDER)
        self.assertIn('IMAGE_DIR="$REPO_DIR/Thingino"', BUILDER)
        self.assertIn('CONFIG_FEATURE_HTTPD_CGI=y', BUILDER)
        self.assertIn('# CONFIG_FEATURE_FORCE_APPLETS is not set', BUILDER)
        self.assertIn('make CAMERA="$CAMERA" br-busybox-rebuild', BUILDER)
        self.assertIn('make CAMERA="$CAMERA" rootfs-ext2', BUILDER)

    def test_native_microphone_and_speaker_mandatory(self):
        for name in (
            "BR2_PACKAGE_THINGINO_RAPTOR_RAC=y",
            "/usr/bin/rac",
            "/usr/sbin/play",
            "/usr/sbin/microphone",
            "/usr/sbin/speaker",
            "T23N microphone/speaker tool missing from SD rootfs",
        ):
            self.assertIn(name, BUILDER)

    def test_docs_must_not_claim_hardware_speedup(self):
        doc = (ROOT / "docs/T23N_LEAN_PROFILE_RU.md").read_text()
        self.assertIn("не измерял", doc)
        self.assertIn("ATBM6012BX", doc)


if __name__ == "__main__":
    unittest.main()
