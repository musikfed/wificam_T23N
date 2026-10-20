#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CAMERA="${CAMERA:-galayou_g2_t23n_sc2336_atbm6012bx}"
THINGINO_DIR="${THINGINO_DIR:-$HOME/myipcam/thingino-firmware}"
PUBLISH="${PUBLISH:-0}"
FAST="${THINGINO_FAST:-0}"

if [ ! -d "$THINGINO_DIR/.git" ] && [ -d "$HOME/thingino-firmware/.git" ]; then
    THINGINO_DIR="$HOME/thingino-firmware"
fi

die() { echo "ERROR: $*" >&2; exit 1; }

[ -d "$THINGINO_DIR/.git" ] || die "Thingino checkout not found: $THINGINO_DIR"
[ -f "$THINGINO_DIR/configs/cameras/$CAMERA/${CAMERA}_defconfig" ] ||     die "Thingino camera profile not found: $CAMERA"

for cmd in git make sha256sum stat find grep debugfs; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd not installed"
done

echo "============================================================"
echo " PegineLab WIFICAM + Thingino MMC image"
echo "============================================================"
echo "Thingino checkout : $THINGINO_DIR"
echo "Camera profile    : $CAMERA"
echo "Target artifact   : $REPO_DIR/Thingino/thingino-t23-sd.bin"
echo
echo "RU: Web UI является обязательной частью этого образа."
echo "EN: The PegineLab WIFICAM Web UI is a mandatory part of this image."
echo

# The current Thingino MMC builder only puts the normal camera rootfs into the
# ext4 p2 image. User overlay/opt files are packed into flash-oriented data.jffs2
# and therefore are not sufficient for an SD-root image. Stage WIFICAM into the
# camera rootfs overlay so it is physically present in rootfs.ext2.
CAM_OVERLAY="$THINGINO_DIR/configs/cameras/$CAMERA/overlay"
mkdir -p "$CAM_OVERLAY"
cp -a "$REPO_DIR/rootfs/." "$CAM_OVERLAY/"
mkdir -p "$CAM_OVERLAY/usr/share/wificam-web"
rm -rf "$CAM_OVERLAY/usr/share/wificam-web"
mkdir -p "$CAM_OVERLAY/usr/share/wificam-web"
cp -a "$REPO_DIR/web/." "$CAM_OVERLAY/usr/share/wificam-web/"

chmod 0755     "$CAM_OVERLAY/etc/init.d/S90wificam"     "$CAM_OVERLAY/etc/init.d/S91wificam-services"     "$CAM_OVERLAY/usr/bin/wificam-camera-ctl"     "$CAM_OVERLAY/usr/bin/wificam-service-ctl"     "$CAM_OVERLAY/usr/bin/wificam-set-web-password"     "$CAM_OVERLAY/usr/share/wificam-web/cgi-bin/api"     "$CAM_OVERLAY/usr/share/wificam-web/cgi-bin/snapshot.jpg"

# Use Thingino's supported user-local config layer for MMC boot settings.
USER_ROOT="$REPO_DIR/out/thingino-user"
USER_CAM="$USER_ROOT/$CAMERA"
rm -rf "$USER_CAM"
mkdir -p "$USER_CAM"
cat > "$USER_CAM/local.fragment" <<'EOF'
# PegineLab WIFICAM T23N SD-root build
BR2_PACKAGE_THINGINO_KOPT_MMC0=y
BR2_PACKAGE_THINGINO_KOPT_MMC0_1BIT=y
BR2_PACKAGE_THINGINO_KOPT_MMC0_BOOT=y
BR2_PACKAGE_THINGINO_UBOOT_ROOT="/dev/mmcblk0p2"
BR2_PACKAGE_THINGINO_UBOOT_ROOTFSTYPE="ext4"
BR2_TARGET_ROOTFS_EXT2=y
BR2_TARGET_ROOTFS_EXT2_4=y
BR2_TARGET_ROOTFS_EXT2_MKFS_OPTIONS="-O ^metadata_csum,^64bit"
BR2_TARGET_ROOTFS_EXT2_SIZE="64M"

# Keep Thingino's own web UI on 80/443, and additionally compile the BusyBox
# httpd applet used by PegineLab WIFICAM on TCP 8080.
BR2_PACKAGE_BUSYBOX_HTTPD=y
EOF

THINGINO_COMMIT="$(git -C "$THINGINO_DIR" rev-parse HEAD)"
echo "Thingino commit   : $THINGINO_COMMIT"

if [ "$FAST" = "1" ]; then
    BUILD_TARGET=fast
else
    BUILD_TARGET=cleanbuild
fi

echo "Build target      : $BUILD_TARGET"
echo

(
    cd "$THINGINO_DIR"
    env IP= THINGINO_USER_DIR="$USER_ROOT"         make CAMERA="$CAMERA" "$BUILD_TARGET"
)

IMAGE="$(find "$THINGINO_DIR/output" -type f -path "*/images/thingino-$CAMERA.bin" -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n1 | cut -d' ' -f2-)"
[ -n "$IMAGE" ] && [ -f "$IMAGE" ] || die "built Thingino MMC image not found"

OUTDIR="$(dirname "$(dirname "$IMAGE")")"
ROOTFS_EXT="$OUTDIR/images/rootfs.ext2"
TARGET="$OUTDIR/target"

[ -f "$ROOTFS_EXT" ] || die "rootfs.ext2 missing: $ROOTFS_EXT"
[ -f "$TARGET/usr/share/wificam-web/index.html" ] || die "WIFICAM index missing from Thingino target rootfs"
[ -x "$TARGET/etc/init.d/S90wificam" ] || die "S90wificam missing/not executable in target rootfs"
[ -x "$TARGET/usr/share/wificam-web/cgi-bin/api" ] || die "WIFICAM API missing/not executable"
[ -x "$TARGET/usr/share/wificam-web/cgi-bin/snapshot.jpg" ] || die "snapshot CGI missing/not executable"
grep -q 'PegineLab WIFICAM T23N' "$TARGET/usr/share/wificam-web/index.html" ||     die "wrong Web UI staged in target"
grep -q '^BR2_PACKAGE_THINGINO_KOPT_MMC0_BOOT=y$' "$OUTDIR/.config" ||     die "MMC0_BOOT is not enabled in final Thingino config"
grep -q '^BR2_PACKAGE_THINGINO_UBOOT_ROOT="/dev/mmcblk0p2"$' "$OUTDIR/.config" ||     die "U-Boot root is not /dev/mmcblk0p2"
grep -q '^BR2_PACKAGE_BUSYBOX_HTTPD=y$' "$OUTDIR/.config" ||     die "BusyBox HTTPD package switch missing"
find "$OUTDIR/build" -path '*/busybox-*/.config' -type f -exec grep -q '^CONFIG_HTTPD=y$' {} \; -print | grep -q . ||     die "BusyBox httpd applet was not compiled"

# Verify the files are not only in Buildroot target/, but in the actual ext4
# filesystem that is embedded as partition 2 of the generated SD image.
debugfs -R 'stat /usr/share/wificam-web/index.html' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' ||     die "WIFICAM index is absent from rootfs.ext2"
debugfs -R 'stat /etc/init.d/S90wificam' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' ||     die "S90wificam is absent from rootfs.ext2"
debugfs -R 'stat /usr/share/wificam-web/cgi-bin/api' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' ||     die "WIFICAM API is absent from rootfs.ext2"

mkdir -p "$REPO_DIR/Thingino"
cp -f "$IMAGE" "$REPO_DIR/Thingino/thingino-t23-sd.bin"

IMAGE_SIZE="$(stat -c '%s' "$REPO_DIR/Thingino/thingino-t23-sd.bin")"
IMAGE_SHA="$(sha256sum "$REPO_DIR/Thingino/thingino-t23-sd.bin" | awk '{print $1}')"
MAX_GITHUB_SIZE=$((95 * 1024 * 1024))
[ "$IMAGE_SIZE" -le "$MAX_GITHUB_SIZE" ] ||     die "canonical image is $IMAGE_SIZE bytes; refusing Git publish above 95 MiB"

printf '%s  %s\n' "$IMAGE_SHA" "thingino-t23-sd.bin" > "$REPO_DIR/Thingino/thingino-t23-sd.bin.sha256"

cat > "$REPO_DIR/Thingino/IMAGE_INFO.txt" <<EOF
PegineLab WIFICAM T23N — canonical Thingino MMC SD candidate

RU:
Профиль-кандидат: $CAMERA
Источник Thingino: $THINGINO_COMMIT
Файл: Thingino/thingino-t23-sd.bin
Размер: $IMAGE_SIZE bytes
SHA256: $IMAGE_SHA
Web UI: ОБЯЗАТЕЛЬНО ПРОВЕРЕНА в rootfs.ext2
Web URL после загрузки: http://CAMERA_IP:8080/
Root: /dev/mmcblk0p2 ext4
Назначение: прямой MMC/SD boot image, НЕ autoupdate payload во SPI.

EN:
Candidate profile: $CAMERA
Thingino source: $THINGINO_COMMIT
File: Thingino/thingino-t23-sd.bin
Size: $IMAGE_SIZE bytes
SHA256: $IMAGE_SHA
Web UI: MANDATORY and VERIFIED inside rootfs.ext2
Web URL after boot: http://CAMERA_IP:8080/
Root: /dev/mmcblk0p2 ext4
Purpose: direct MMC/SD boot image, NOT an SPI autoupdate payload.
EOF

echo
echo "THINGINO WIFICAM SD IMAGE: VERIFIED"
echo "Source image : $IMAGE"
echo "Canonical    : Thingino/thingino-t23-sd.bin"
echo "Size         : $IMAGE_SIZE bytes"
echo "SHA256       : $IMAGE_SHA"
echo "Web UI       : VERIFIED inside p2 rootfs.ext2"
echo "Web URL      : http://CAMERA_IP:8080/"
echo

if [ "$PUBLISH" = "1" ]; then
    BRANCH="$(git -C "$REPO_DIR" branch --show-current)"
    [ "$BRANCH" = "mymarrchWFcam" ] || die "refusing publish from branch: $BRANCH"

    git -C "$REPO_DIR" add -f         Thingino/thingino-t23-sd.bin         Thingino/thingino-t23-sd.bin.sha256         Thingino/IMAGE_INFO.txt

    if git -C "$REPO_DIR" diff --cached --quiet; then
        echo "Git: canonical image already committed."
    else
        git -C "$REPO_DIR" commit -m "firmware(thingino): verify relevant T23N SD image with WIFICAM / проверка релевантного T23N SD образа с WIFICAM"
    fi
    git -C "$REPO_DIR" push origin "$BRANCH"
    echo "Git publish: OK ($BRANCH)"
else
    echo "Not pushed. To build + commit + push in one run:"
    echo "  PUBLISH=1 sh scripts/build_thingino_wificam_image.sh"
fi
