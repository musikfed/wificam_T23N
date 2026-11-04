"""Offline guard for generic and personalized SD build handling.

Do not read local Wi-Fi secrets or invoke a cross compiler in tests.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class FirmwareWiFiContractTests(unittest.TestCase):
    def test_generic_candidate_does_not_require_private_wifi(self):
        source = (ROOT / "scripts/build_thingino_wificam_image.sh").read_text()
        self.assertIn('IMAGE_DIR="$REPO_DIR/out/candidate-sd"', source)
        self.assertIn('if [ "$IMAGE_DIR" = "$REPO_DIR/out/private-sd" ]; then', source)
        self.assertNotIn('if [ "$IMAGE_DIR" != "$REPO_DIR/Thingino" ]; then', source)
        self.assertIn('private Wi-Fi config did not reach rootfs.ext2', source)

    def test_private_wifi_must_not_enter_git_reference(self):
        source = (ROOT / "scripts/build_thingino_wificam_image.sh").read_text()
        self.assertIn('IMAGE_DIR="$REPO_DIR/out/private-sd"', source)
        self.assertIn('refusing PUBLISH=1 with embedded Wi-Fi credentials', source)
        self.assertIn('IMAGE_PATH="$IMAGE_DIR/thingino-t23-sd.bin"', source)
        self.assertIn('"$IMAGE_PATH.sha256"', source)

    def test_recovery_and_audio_stay_present(self):
        source = (ROOT / "scripts/build_thingino_wificam_image.sh").read_text()
        for value in (
            "BR2_PACKAGE_DROPBEAR=y",
            "BR2_PACKAGE_THINGINO_RAPTOR_RAC=y",
            "BR2_PACKAGE_THINGINO_KOPT_MMC0_BOOT=y",
            "BR2_PACKAGE_THINGINO_KOPT_DWC2=y",
            "CONFIG_FEATURE_HTTPD_CGI=y",
            "CONFIG_FEATURE_HTTPD_BASIC_AUTH=y",
            "WIFICAM_WEBRTC",
        ):
            with self.subTest(feature=value):
                self.assertIn(value, source)


if __name__ == "__main__":
    unittest.main()
