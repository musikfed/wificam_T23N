#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CAMERA="${CAMERA:-galayou_g2_t23n_sc2336_atbm6012bx}"
THINGINO_REF="${THINGINO_REF:-9925f46f73b9c39ec8d2a65134b18c94e6fdfb97}"
THINGINO_URL="${THINGINO_URL:-https://github.com/themactep/thingino-firmware.git}"
PUBLISH="${PUBLISH:-0}"
FAST="${THINGINO_FAST:-0}"

die() { echo "ERROR: $*" >&2; exit 1; }

for cmd in git make sha256sum stat find grep debugfs; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd not installed"
done

resolve_thingino_dir() {
    if [ -n "${THINGINO_DIR:-}" ]; then
        printf '%s\n' "$THINGINO_DIR"
        return 0
    fi

    for d in \
        "$HOME/myipcam/thingino-firmware" \
        "$HOME/thingino-firmware" \
        "$HOME/myipcam/Thingino/thingino-firmware"
    do
        if [ -d "$d/.git" ]; then
            printf '%s\n' "$d"
            return 0
        fi
    done

    printf '%s\n' "$HOME/myipcam/thingino-firmware"
}

THINGINO_DIR="$(resolve_thingino_dir)"

prepare_thingino_checkout() {
    if [ ! -d "$THINGINO_DIR/.git" ]; then
        echo "Thingino checkout not found; cloning pinned upstream source..."
        mkdir -p "$(dirname "$THINGINO_DIR")"
        git clone --recurse-submodules "$THINGINO_URL" "$THINGINO_DIR"
    fi

    [ -d "$THINGINO_DIR/.git" ] || die "Thingino checkout unavailable: $THINGINO_DIR"

    if [ -n "$(git -C "$THINGINO_DIR" status --porcelain)" ]; then
        die "Thingino checkout has local changes: $THINGINO_DIR"
    fi

    if ! git -C "$THINGINO_DIR" cat-file -e "$THINGINO_REF^{commit}" 2>/dev/null; then
        echo "Fetching pinned Thingino commit $THINGINO_REF ..."
        git -C "$THINGINO_DIR" fetch origin "$THINGINO_REF"
    fi

    git -C "$THINGINO_DIR" checkout --detach "$THINGINO_REF"
    git -C "$THINGINO_DIR" submodule sync --recursive
    git -C "$THINGINO_DIR" submodule update --init --recursive

    ACTUAL="$(git -C "$THINGINO_DIR" rev-parse HEAD)"
    [ "$ACTUAL" = "$THINGINO_REF" ] || die "Thingino HEAD mismatch: $ACTUAL"

    [ -f "$THINGINO_DIR/configs/cameras/$CAMERA/${CAMERA}_defconfig" ] || \
        die "Thingino camera profile not found: $CAMERA"
}

echo "============================================================"
echo " PegineLab WIFICAM + Thingino MMC image"
echo "============================================================"
echo "Project checkout  : $REPO_DIR"
echo "Thingino checkout : $THINGINO_DIR"
echo "Pinned Thingino   : $THINGINO_REF"
echo "Camera profile    : $CAMERA"
echo "Target artifact   : $REPO_DIR/Thingino/thingino-t23-sd.bin"
echo
echo "RU: Web UI является обязательной частью этого образа."
echo "EN: The PegineLab WIFICAM Web UI is a mandatory part of this image."
echo

if [ "$PUBLISH" = "1" ] && ! git -C "$REPO_DIR" diff --cached --quiet; then
    die "refusing PUBLISH=1 because unrelated files are already staged in the project repo"
fi

prepare_thingino_checkout

# MMC mode boots p2/rootfs.ext2 directly. Thingino user/overlay normally feeds
# data.jffs2, which is not mounted as the root device in this SD-root mode.
# Build a dedicated Buildroot rootfs overlay and inject WIFICAM into rootfs.ext2.
ROOTFS_OVERLAY="$REPO_DIR/out/thingino-wificam-rootfs-overlay"
sh "$REPO_DIR/scripts/package_rootfs_overlay.sh" "$ROOTFS_OVERLAY"

USER_ROOT="$REPO_DIR/out/thingino-user"
USER_CAM="$USER_ROOT/$CAMERA"
rm -rf "$USER_CAM"
mkdir -p "$USER_CAM"

cat > "$USER_CAM/local.fragment" <<EOF
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

# Thingino BusyBox httpd webserver choice enables CGI + Basic Auth + MD5.
BR2_PACKAGE_THINGINO_WEBSERVER_BUSYBOX=y

# Mandatory PegineLab/WIFICAM files are embedded directly into p2/rootfs.ext2.
BR2_ROOTFS_OVERLAY="\$(BR2_EXTERNAL_THINGINO_PATH)/overlay $ROOTFS_OVERLAY"
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
    env IP= THINGINO_USER_DIR="$USER_ROOT" \
        make CAMERA="$CAMERA" "$BUILD_TARGET"
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

grep -q 'PegineLab WIFICAM T23N' "$TARGET/usr/share/wificam-web/index.html" || \
    die "wrong Web UI staged in target"
grep -q '^BR2_PACKAGE_THINGINO_KOPT_MMC0_BOOT=y$' "$OUTDIR/.config" || \
    die "MMC0_BOOT is not enabled in final Thingino config"
grep -q '^BR2_PACKAGE_THINGINO_UBOOT_ROOT="/dev/mmcblk0p2"$' "$OUTDIR/.config" || \
    die "U-Boot root is not /dev/mmcblk0p2"
grep -q '^BR2_PACKAGE_THINGINO_WEBSERVER_BUSYBOX=y$' "$OUTDIR/.config" || \
    die "Thingino BusyBox webserver choice is not enabled"

BUSYBOX_CONFIG="$(find "$OUTDIR/build" -path '*/busybox-*/.config' -type f | head -n1)"
[ -n "$BUSYBOX_CONFIG" ] && [ -f "$BUSYBOX_CONFIG" ] || die "BusyBox .config not found"
for opt in \
    CONFIG_HTTPD \
    CONFIG_FEATURE_HTTPD_BASIC_AUTH \
    CONFIG_FEATURE_HTTPD_AUTH_MD5 \
    CONFIG_FEATURE_HTTPD_CGI \
    CONFIG_FEATURE_HTTPD_CONFIG_WITH_SCRIPT_INTERPR
do
    grep -q "^$opt=y$" "$BUSYBOX_CONFIG" || die "BusyBox HTTP feature missing: $opt"
done

# Verify mandatory WIFICAM files in the actual ext4 filesystem embedded as p2.
debugfs -R 'stat /usr/share/wificam-web/index.html' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM index is absent from rootfs.ext2"
debugfs -R 'stat /etc/init.d/S90wificam' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "S90wificam is absent from rootfs.ext2"
debugfs -R 'stat /usr/share/wificam-web/cgi-bin/api' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM API is absent from rootfs.ext2"
debugfs -R 'stat /usr/share/wificam-web/cgi-bin/snapshot.jpg' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM snapshot CGI is absent from rootfs.ext2"

mkdir -p "$REPO_DIR/Thingino"
cp -f "$IMAGE" "$REPO_DIR/Thingino/thingino-t23-sd.bin"

IMAGE_SIZE="$(stat -c '%s' "$REPO_DIR/Thingino/thingino-t23-sd.bin")"
IMAGE_SHA="$(sha256sum "$REPO_DIR/Thingino/thingino-t23-sd.bin" | awk '{print $1}')"

HISTORICAL_REFERENCE="/mnt/d/Thingino/thingino-t23-sd.bin"
HISTORICAL_SHA="not-present"
HISTORICAL_SIZE="not-present"
if [ -f "$HISTORICAL_REFERENCE" ]; then
    HISTORICAL_SHA="$(sha256sum "$HISTORICAL_REFERENCE" | awk '{print $1}')"
    HISTORICAL_SIZE="$(stat -c '%s' "$HISTORICAL_REFERENCE")"
fi

MAX_GITHUB_SIZE=$((95 * 1024 * 1024))
[ "$IMAGE_SIZE" -le "$MAX_GITHUB_SIZE" ] || \
    die "canonical image is $IMAGE_SIZE bytes; refusing Git publish above 95 MiB"

printf '%s  %s\n' "$IMAGE_SHA" "thingino-t23-sd.bin" > "$REPO_DIR/Thingino/thingino-t23-sd.bin.sha256"

cat > "$REPO_DIR/Thingino/IMAGE_INFO.txt" <<EOF
PegineLab WIFICAM T23N — canonical Thingino MMC SD candidate

RU:
Профиль-кандидат: $CAMERA
Источник Thingino: $THINGINO_COMMIT
Файл: Thingino/thingino-t23-sd.bin
Размер: $IMAGE_SIZE bytes
SHA256: $IMAGE_SHA
Исторический локальный reference: $HISTORICAL_REFERENCE
Reference size: $HISTORICAL_SIZE
Reference SHA256: $HISTORICAL_SHA
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
Historical local reference: $HISTORICAL_REFERENCE
Reference size: $HISTORICAL_SIZE
Reference SHA256: $HISTORICAL_SHA
Web UI: MANDATORY and VERIFIED inside rootfs.ext2
Web URL after boot: http://CAMERA_IP:8080/
Root: /dev/mmcblk0p2 ext4
Purpose: direct MMC/SD boot image, NOT an SPI autoupdate payload.
EOF

echo
echo "THINGINO WIFICAM SD IMAGE: VERIFIED"
echo "Source image  : $IMAGE"
echo "Canonical     : Thingino/thingino-t23-sd.bin"
echo "Size          : $IMAGE_SIZE bytes"
echo "SHA256        : $IMAGE_SHA"
echo "Historical    : $HISTORICAL_REFERENCE"
echo "Historical SHA: $HISTORICAL_SHA"
echo "Web UI        : VERIFIED inside p2 rootfs.ext2"
echo "Web URL       : http://CAMERA_IP:8080/"
echo

if [ "$PUBLISH" = "1" ]; then
    BRANCH="$(git -C "$REPO_DIR" branch --show-current)"
    [ "$BRANCH" = "mymarrchWFcam" ] || die "refusing publish from branch: $BRANCH"

    git -C "$REPO_DIR" add -f \
        Thingino/thingino-t23-sd.bin \
        Thingino/thingino-t23-sd.bin.sha256 \
        Thingino/IMAGE_INFO.txt

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
