#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT="${1:-$REPO_DIR/out/rootfs-overlay}"

# Generate the tiny original chiptune on the build host so binary audio does not
# need to live in Git.
if [ ! -f "$REPO_DIR/web/assets/boot-jingle.wav" ] && command -v python3 >/dev/null 2>&1; then
    python3 "$REPO_DIR/tools/generate_boot_jingle.py"
fi

rm -rf "$OUT"
mkdir -p "$OUT/usr/share/wificam-web"

# Package the complete maintained rootfs overlay, including SD-only
# /etc/fw_env.config. This avoids silently forgetting future rootfs files.
cp -R "$REPO_DIR/rootfs/." "$OUT/"
cp -R "$REPO_DIR/web/." "$OUT/usr/share/wificam-web/"

# Decode the compact PegineLab logo source into a PNG for framebuffer tools.
if [ -f "$REPO_DIR/branding/peginelab-logo.png.b64" ]; then
    mkdir -p "$OUT/usr/share/wificam-web/assets"
    base64 -d "$REPO_DIR/branding/peginelab-logo.png.b64" >       "$OUT/usr/share/wificam-web/assets/peginelab-logo.png"
fi

chmod 0755   "$OUT/etc/init.d/S05peginelab-boot"   "$OUT/etc/init.d/S90wificam"   "$OUT/etc/init.d/S91wificam-services"   "$OUT/usr/bin/wificam-camera-ctl"   "$OUT/usr/bin/wificam-service-ctl"   "$OUT/usr/bin/wificam-set-web-password"   "$OUT/usr/share/wificam-web/cgi-bin/api" \
  "$OUT/usr/share/wificam-web/cgi-bin/snapshot.jpg"

chmod 0644 "$OUT/etc/fw_env.config"

mkdir -p "$REPO_DIR/out"
tar -C "$OUT" -czf "$REPO_DIR/out/wificam-rootfs-overlay.tar.gz" .

echo "Overlay: $OUT"
echo "Archive: $REPO_DIR/out/wificam-rootfs-overlay.tar.gz"
