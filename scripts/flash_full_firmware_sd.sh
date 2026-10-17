#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DEV="${1:-}"
KERNEL="${2:-$HOME/myipcam/build/kernel/arch/mips/boot/uImage}"

OPENIPC_URL="https://github.com/OpenIPC/firmware/releases/download/latest/openipc.t23-nor-lite.tgz"
OPENIPC_SHA256="e039f89137ba091e08cf4e6ebc766ff3d9cce0ad10410cf6b56994db33d7c00c"
OPENIPC_SIZE=6185295
BUNDLE="$REPO_DIR/out/openipc.t23-nor-lite.tgz"

usage() {
    echo "Usage: sudo $0 /dev/sdX [uImage]" >&2
    echo "Writes a FULL OpenIPC T23 rootfs + WIFICAM/PegineLab overlay to the existing ROOTFS partition." >&2
    echo "It does NOT repartition the card." >&2
    exit 2
}

[ -n "$DEV" ] || usage
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo/root" >&2; exit 1; }
[ -b "$DEV" ] || { echo "Not a block device: $DEV" >&2; exit 1; }
[ "$(lsblk -dn -o TYPE "$DEV" 2>/dev/null)" = "disk" ] || { echo "$DEV is not a whole disk" >&2; exit 1; }

case "$DEV" in
  /dev/sd[a-z]|/dev/mmcblk[0-9]) ;;
  *) echo "Refusing suspicious device name: $DEV" >&2; exit 1 ;;
esac

part() {
    case "$DEV" in
      /dev/mmcblk*) echo "${DEV}p$1" ;;
      *) echo "${DEV}$1" ;;
    esac
}

P1="$(part 1)"
P2="$(part 2)"
P3="$(part 3)"

for p in "$P1" "$P2" "$P3"; do
    [ -b "$p" ] || { echo "Missing expected partition: $p" >&2; exit 1; }
done

for cmd in curl tar unsquashfs sha256sum blkid mount umount lsblk; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Missing host tool: $cmd" >&2
        echo "Install with: sudo apt install -y curl squashfs-tools" >&2
        exit 1
    }
done

ROOT_SRC="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
case "$ROOT_SRC" in
  "$DEV"*) echo "REFUSING: $DEV contains the running WSL root filesystem" >&2; exit 1 ;;
esac

label_of() { blkid -s LABEL -o value "$1" 2>/dev/null || true; }
fs_of() { blkid -s TYPE -o value "$1" 2>/dev/null || true; }

[ "$(label_of "$P1")" = "BOOT" ] || { echo "REFUSING: $P1 is not LABEL=BOOT" >&2; exit 1; }
[ "$(label_of "$P2")" = "ROOTFS" ] || { echo "REFUSING: $P2 is not LABEL=ROOTFS" >&2; exit 1; }
[ "$(label_of "$P3")" = "MEDIA" ] || { echo "REFUSING: $P3 is not LABEL=MEDIA" >&2; exit 1; }
[ "$(fs_of "$P1")" = "vfat" ] || { echo "REFUSING: $P1 is not vfat" >&2; exit 1; }
[ "$(fs_of "$P2")" = "ext4" ] || { echo "REFUSING: $P2 is not ext4" >&2; exit 1; }
[ "$(fs_of "$P3")" = "ext4" ] || { echo "REFUSING: $P3 is not ext4" >&2; exit 1; }

echo "FULL FIRMWARE target:"
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM "$DEV"
echo
echo "ROOTFS source: official OpenIPC T23 lite + WIFICAM/PegineLab overlay"
echo "OpenIPC bundle SHA-256: $OPENIPC_SHA256"
echo
printf "Type FLASH-ROOTFS:%s to replace only %s: " "$DEV" "$P2"
read confirm
[ "$confirm" = "FLASH-ROOTFS:$DEV" ] || { echo "Cancelled."; exit 1; }

mkdir -p "$REPO_DIR/out"

need_download=1
if [ -f "$BUNDLE" ]; then
    got="$(sha256sum "$BUNDLE" | awk '{print $1}')"
    [ "$got" = "$OPENIPC_SHA256" ] && need_download=0
fi

if [ "$need_download" -eq 1 ]; then
    echo "Downloading pinned OpenIPC T23 lite rootfs bundle..."
    rm -f "$BUNDLE.tmp"
    curl -fL --retry 3 --connect-timeout 20 -o "$BUNDLE.tmp" "$OPENIPC_URL"
    got_size="$(wc -c < "$BUNDLE.tmp" | tr -d ' ')"
    [ "$got_size" -eq "$OPENIPC_SIZE" ] || {
        rm -f "$BUNDLE.tmp"
        echo "REFUSING: OpenIPC asset size changed ($got_size != $OPENIPC_SIZE)." >&2
        echo "The 'latest' release moved; update this branch before flashing." >&2
        exit 1
    }
    echo "$OPENIPC_SHA256  $BUNDLE.tmp" | sha256sum -c -
    mv "$BUNDLE.tmp" "$BUNDLE"
else
    echo "Using cached verified OpenIPC bundle: $BUNDLE"
fi

echo "$OPENIPC_SHA256  $BUNDLE" | sha256sum -c -

WORK="$(mktemp -d)"
ROOT_MNT="$(mktemp -d)"
BOOT_MNT="$(mktemp -d)"
MEDIA_MNT="$(mktemp -d)"
cleanup() {
    umount "$MEDIA_MNT" 2>/dev/null || true
    umount "$BOOT_MNT" 2>/dev/null || true
    umount "$ROOT_MNT" 2>/dev/null || true
    rm -rf "$WORK"
    rmdir "$MEDIA_MNT" "$BOOT_MNT" "$ROOT_MNT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "Extracting OpenIPC release..."
tar -xzf "$BUNDLE" -C "$WORK"
ROOTFS_IMG="$(find "$WORK" -type f -name 'rootfs.squashfs.t23' -print -quit)"
OPENIPC_KERNEL="$(find "$WORK" -type f -name 'uImage.t23' -print -quit)"
[ -n "$ROOTFS_IMG" ] || {
    echo "REFUSING: rootfs.squashfs.t23 not found in OpenIPC bundle" >&2
    exit 1
}
[ -n "$OPENIPC_KERNEL" ] || {
    echo "REFUSING: uImage.t23 not found in OpenIPC bundle" >&2
    exit 1
}

unsquashfs -s "$ROOTFS_IMG" >/dev/null
unsquashfs -d "$WORK/base-rootfs" "$ROOTFS_IMG" >/dev/null

[ -x "$WORK/base-rootfs/bin/sh" ] || {
    echo "REFUSING: extracted OpenIPC rootfs has no executable /bin/sh" >&2
    exit 1
}
[ -x "$WORK/base-rootfs/init" ] || {
    echo "REFUSING: extracted OpenIPC rootfs has no executable /init" >&2
    exit 1
}

echo "Building WIFICAM/PegineLab overlay..."
sh "$REPO_DIR/scripts/package_rootfs_overlay.sh"
tar -C "$WORK/base-rootfs" -xzf "$REPO_DIR/out/wificam-rootfs-overlay.tar.gz"

mkdir -p     "$WORK/base-rootfs/data/services"     "$WORK/base-rootfs/data/vpn"     "$WORK/base-rootfs/mnt/media"     "$WORK/base-rootfs/etc/wificam"

# OpenIPC lite normally starts Dropbear itself. WIFICAM owns SSH autostart:
# keep the script for recovery/reference but remove it from the normal S* boot glob.
if [ -e "$WORK/base-rootfs/etc/init.d/S50dropbear" ]; then
    mv "$WORK/base-rootfs/etc/init.d/S50dropbear"        "$WORK/base-rootfs/etc/init.d/K50dropbear.wificam-disabled"
fi

cat > "$WORK/base-rootfs/etc/wificam/rootfs-source.txt" <<EOF
Base: OpenIPC official t23 lite
Asset: openipc.t23-nor-lite.tgz
SHA256: $OPENIPC_SHA256
WIFICAM branch: mymarrchWFcam
Installed: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
EOF

chmod 0755     "$WORK/base-rootfs/etc/init.d/S05peginelab-boot"     "$WORK/base-rootfs/etc/init.d/S90wificam"     "$WORK/base-rootfs/etc/init.d/S91wificam-services"     "$WORK/base-rootfs/usr/bin/wificam-camera-ctl"     "$WORK/base-rootfs/usr/bin/wificam-service-ctl"     "$WORK/base-rootfs/usr/bin/wificam-set-web-password"     "$WORK/base-rootfs/usr/share/wificam-web/cgi-bin/api"

for n in 1 2 3; do
    umount "$(part "$n")" 2>/dev/null || true
done

echo "Installing full rootfs to $P2 ..."
mount "$P2" "$ROOT_MNT"
find "$ROOT_MNT" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
cp -a "$WORK/base-rootfs/." "$ROOT_MNT/"

[ -x "$ROOT_MNT/bin/sh" ] || { echo "Rootfs copy verification failed: /bin/sh" >&2; exit 1; }
[ -x "$ROOT_MNT/init" ] || { echo "Rootfs copy verification failed: /init" >&2; exit 1; }
[ -x "$ROOT_MNT/etc/init.d/S90wificam" ] || { echo "Rootfs copy verification failed: S90wificam" >&2; exit 1; }
[ -f "$ROOT_MNT/usr/share/wificam-web/index.html" ] || { echo "Rootfs copy verification failed: Web UI" >&2; exit 1; }

echo "Refreshing BOOT files..."
mount "$P1" "$BOOT_MNT"
if [ -f "$KERNEL" ]; then
    cp "$KERNEL" "$BOOT_MNT/uImage"
fi
# Keep the matching official OpenIPC kernel as a UART/U-Boot fallback. The
# custom known-good build remains the primary /uImage.
cp "$OPENIPC_KERNEL" "$BOOT_MNT/uImage.openipc.t23"
if [ -f "$REPO_DIR/branding/peginelab-logo.png.b64" ]; then
    base64 -d "$REPO_DIR/branding/peginelab-logo.png.b64" > "$BOOT_MNT/peginelab-logo.png"
fi
[ -f "$REPO_DIR/web/assets/boot-jingle.wav" ] &&     cp "$REPO_DIR/web/assets/boot-jingle.wav" "$BOOT_MNT/boot-jingle.wav"

echo "Checking MEDIA..."
mount "$P3" "$MEDIA_MNT"
mkdir -p "$MEDIA_MNT/recordings" "$MEDIA_MNT/snapshots" "$MEDIA_MNT/events"

sync

echo
echo "FULL ROOTFS INSTALLED:"
du -sh "$ROOT_MNT" 2>/dev/null || true
ls -lh "$BOOT_MNT/uImage" "$BOOT_MNT/uImage.openipc.t23" "$BOOT_MNT/peginelab-logo.png" "$BOOT_MNT/boot-jingle.wav" 2>/dev/null || true
echo
echo "Rootfs sanity:"
ls -l "$ROOT_MNT/bin/sh" "$ROOT_MNT/init" "$ROOT_MNT/etc/init.d/S90wificam"
echo
echo "WIFICAM bootstrap UI: http://<camera-ip>:8080/"
echo "Majestic/OpenIPC UI remains on port 80."
echo "Do NOT expose the unauthenticated bootstrap UI to the public Internet."
echo
echo "Card is ready for U-Boot SD/RAM boot validation. Factory SPI/NOR/NAND was not touched."
