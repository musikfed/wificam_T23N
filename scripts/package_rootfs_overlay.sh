#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT="${1:-$REPO_DIR/out/rootfs-overlay}"

# Generate the tiny original chiptune on the build host so binary audio does not
# need to live in Git. The generated file is ignored by .gitignore.
if [ ! -f "$REPO_DIR/web/assets/boot-jingle.wav" ] && command -v python3 >/dev/null 2>&1; then
    python3 "$REPO_DIR/tools/generate_boot_jingle.py"
fi

rm -rf "$OUT"
mkdir -p "$OUT/usr/share/wificam-web" "$OUT/etc/init.d" "$OUT/etc/wificam" "$OUT/usr/bin"

cp -R "$REPO_DIR/web/." "$OUT/usr/share/wificam-web/"

# Decode the compact PegineLab logo source into a PNG for framebuffer tools.
if [ -f "$REPO_DIR/branding/peginelab-logo.png.b64" ]; then
    mkdir -p "$OUT/usr/share/wificam-web/assets"
    base64 -d "$REPO_DIR/branding/peginelab-logo.png.b64" >       "$OUT/usr/share/wificam-web/assets/peginelab-logo.png"
fi

cp "$REPO_DIR/rootfs/etc/init.d/S05peginelab-boot" "$OUT/etc/init.d/S05peginelab-boot"
cp "$REPO_DIR/rootfs/etc/init.d/S90wificam" "$OUT/etc/init.d/S90wificam"
cp "$REPO_DIR/rootfs/etc/init.d/S91wificam-services" "$OUT/etc/init.d/S91wificam-services"
cp "$REPO_DIR/rootfs/etc/wificam/wificam.conf" "$OUT/etc/wificam/wificam.conf"
cp "$REPO_DIR/rootfs/usr/bin/wificam-camera-ctl" "$OUT/usr/bin/wificam-camera-ctl"
cp "$REPO_DIR/rootfs/usr/bin/wificam-service-ctl" "$OUT/usr/bin/wificam-service-ctl"
cp "$REPO_DIR/rootfs/usr/bin/wificam-set-web-password" "$OUT/usr/bin/wificam-set-web-password"

chmod 0755   "$OUT/etc/init.d/S05peginelab-boot"   "$OUT/etc/init.d/S90wificam"   "$OUT/etc/init.d/S91wificam-services"   "$OUT/usr/bin/wificam-camera-ctl"   "$OUT/usr/bin/wificam-service-ctl"   "$OUT/usr/bin/wificam-set-web-password"   "$OUT/usr/share/wificam-web/cgi-bin/api"

mkdir -p "$REPO_DIR/out"
tar -C "$OUT" -czf "$REPO_DIR/out/wificam-rootfs-overlay.tar.gz" .

echo "Overlay: $OUT"
echo "Archive: $REPO_DIR/out/wificam-rootfs-overlay.tar.gz"
