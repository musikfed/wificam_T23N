#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DEV="${1:-}"

# Resolve the invoking user's home even when this script runs under sudo.
if [ -n "${SUDO_USER:-}" ] && command -v getent >/dev/null 2>&1; then
    USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
    USER_HOME="$HOME"
fi

KERNEL="${2:-$USER_HOME/myipcam/build/kernel/arch/mips/boot/uImage}"
BOOTLOADER="${3:-$REPO_DIR/out/u-boot-t23n-sd.bin}"
KERNEL_CONFIG="${KERNEL_CONFIG:-$USER_HOME/myipcam/build/kernel/.config}"

OPENIPC_URL="https://github.com/OpenIPC/firmware/releases/download/latest/openipc.t23-nor-lite.tgz"
OPENIPC_SHA256="e039f89137ba091e08cf4e6ebc766ff3d9cce0ad10410cf6b56994db33d7c00c"
OPENIPC_SIZE=6185295
BUNDLE="$REPO_DIR/out/openipc.t23-nor-lite.tgz"

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
    echo "Usage: sudo $0 /dev/sdX [autonomous-uImage] [u-boot-t23n-sd.bin]" >&2
    echo "DESTROYS and repartitions the entire SD card." >&2
    echo "Target: T23/T23N with the SPI/NOR boot flash physically absent." >&2
    exit 2
}

[ -n "$DEV" ] || usage
[ "$(id -u)" -eq 0 ] || die "run with sudo/root"
[ -b "$DEV" ] || die "not a block device: $DEV"
[ "$(lsblk -dn -o TYPE "$DEV" 2>/dev/null)" = "disk" ] || die "$DEV is not a whole disk"

case "$DEV" in
  /dev/sd[a-z]|/dev/mmcblk[0-9]) ;;
  *) die "refusing suspicious device name: $DEV" ;;
esac

ROOT_SRC="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
case "$ROOT_SRC" in
  "$DEV"*) die "$DEV contains the running root filesystem" ;;
esac

for cmd in curl tar unsquashfs sha256sum stat lsblk od python3; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Missing host tool: $cmd" >&2
        echo "Install host requirements with:" >&2
        echo "  sudo apt install -y curl squashfs-tools dosfstools fdisk e2fsprogs" >&2
        exit 1
    }
done

[ -f "$KERNEL" ] || die "autonomous-SD kernel not found: $KERNEL"
[ -f "$BOOTLOADER" ] || {
    echo "SD bootloader not found: $BOOTLOADER" >&2
    echo "Build it first as your normal WSL user:" >&2
    echo "  sh scripts/build_sd_bootloader.sh" >&2
    exit 1
}
[ -f "$KERNEL_CONFIG" ] || die "kernel config not found: $KERNEL_CONFIG"
OVERLAY_ARCHIVE="$REPO_DIR/out/wificam-rootfs-overlay.tar.gz"
[ -s "$OVERLAY_ARCHIVE" ] || {
    echo "WIFICAM overlay archive missing: $OVERLAY_ARCHIVE" >&2
    echo "Build it first as the normal user:" >&2
    echo "  sh scripts/package_rootfs_overlay.sh" >&2
    exit 1
}

require_kernel_y() {
    grep -q "^$1=y$" "$KERNEL_CONFIG" || die "$1 is not built-in in $KERNEL_CONFIG; run scripts/build_kernel.sh"
}
require_kernel_y CONFIG_MMC
require_kernel_y CONFIG_MMC_BLOCK
require_kernel_y CONFIG_JZMMC_V12
require_kernel_y CONFIG_JZMMC_V12_MMC0
require_kernel_y CONFIG_EXT4_FS
require_kernel_y CONFIG_MSDOS_PARTITION
require_kernel_y CONFIG_DEVTMPFS
require_kernel_y CONFIG_DEVTMPFS_MOUNT

magic="$(od -An -tx4 -N4 "$BOOTLOADER" | tr -d ' \n')"
[ "$magic" = "4d53504c" ] || die "$BOOTLOADER is not an MMC SPL image (magic=$magic)"

echo "AUTONOMOUS SD FIRMWARE TARGET:"
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS "$DEV"
echo
echo "SPI/NOR boot flash : NOT USED / may be physically absent"
echo "BootROM -> SD SPL  : raw sector 34"
echo "U-Boot -> kernel   : BOOT FAT32 /uImage"
echo "Linux root         : SD partition 2, ext4"
echo "Camera media       : SD partition 3, ext4, 20 GiB"
echo
printf "Type AUTONOMOUS-SD:%s to ERASE AND REBUILD this SD: " "$DEV"
read confirm
[ "$confirm" = "AUTONOMOUS-SD:$DEV" ] || { echo "Cancelled."; exit 1; }

mkdir -p "$REPO_DIR/out"

need_download=1
if [ -f "$BUNDLE" ]; then
    got="$(sha256sum "$BUNDLE" | awk '{print $1}')"
    [ "$got" = "$OPENIPC_SHA256" ] && need_download=0
fi

if [ "$need_download" -eq 1 ]; then
    echo "Downloading pinned OpenIPC T23 userspace bundle..."
    rm -f "$BUNDLE.tmp"
    curl -fL --retry 3 --connect-timeout 20 -o "$BUNDLE.tmp" "$OPENIPC_URL"
    got_size="$(wc -c < "$BUNDLE.tmp" | tr -d ' ')"
    [ "$got_size" -eq "$OPENIPC_SIZE" ] || {
        rm -f "$BUNDLE.tmp"
        die "OpenIPC asset changed ($got_size != $OPENIPC_SIZE); update the repository before flashing"
    }
    echo "$OPENIPC_SHA256  $BUNDLE.tmp" | sha256sum -c -
    mv "$BUNDLE.tmp" "$BUNDLE"
fi
echo "$OPENIPC_SHA256  $BUNDLE" | sha256sum -c -

WORK="$(mktemp -d)"
ROOTFS_TAR="$WORK/wificam-t23n-sd-rootfs.tar.gz"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

echo "Extracting OpenIPC T23 userspace..."
tar -xzf "$BUNDLE" -C "$WORK"
ROOTFS_IMG="$(find "$WORK" -type f -name 'rootfs.squashfs.t23' -print -quit)"
[ -n "$ROOTFS_IMG" ] || die "rootfs.squashfs.t23 not found in OpenIPC bundle"

unsquashfs -s "$ROOTFS_IMG" >/dev/null
unsquashfs -d "$WORK/base-rootfs" "$ROOTFS_IMG" >/dev/null

[ -x "$WORK/base-rootfs/bin/sh" ] || die "OpenIPC base rootfs has no executable /bin/sh"
[ -x "$WORK/base-rootfs/init" ] || die "OpenIPC base rootfs has no executable /init"

echo "Applying prebuilt WIFICAM/PegineLab rootfs overlay..."
tar -C "$WORK/base-rootfs" -xzf "$OVERLAY_ARCHIVE"


# OpenIPC T23 normally loads jzmmc_v12 as a module late in userspace.
# SD-root needs that host controller built into the kernel before / is mounted.
# Skip the duplicate modprobe so camera-driver setup does not abort.
LOAD_INGENIC="$WORK/base-rootfs/usr/bin/load_ingenic"
[ -f "$LOAD_INGENIC" ] || die "OpenIPC T23 load_ingenic not found"
python3 - "$LOAD_INGENIC" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()
old = """lsmod | grep -q "jzmmc_v12"
if [ $? -ne 0 ]; then
\tmodprobe jzmmc_v12 detect_pin=$(fw_printenv -n gpio_mmc || echo 59)
\tcheck_return "modprobe mmc"
fi
"""
new = """# WIFICAM autonomous-SD: mmc0 is built into the kernel because it hosts /.
# Loading jzmmc_v12.ko again would fail and stop this script.
if ! grep -q 'root=/dev/mmcblk0p2' /proc/cmdline; then
\tlsmod | grep -q "jzmmc_v12"
\tif [ $? -ne 0 ]; then
\t\tmodprobe jzmmc_v12 detect_pin=$(fw_printenv -n gpio_mmc || echo 59)
\t\tcheck_return "modprobe mmc"
\tfi
fi
"""
if old not in s:
    raise SystemExit("pinned OpenIPC load_ingenic MMC block not found")
p.write_text(s.replace(old, new, 1))
PY

grep -q "root=/dev/mmcblk0p2" "$LOAD_INGENIC" || die "load_ingenic SD patch verification failed"
grep -Eq '^/dev/mmcblk0[[:space:]]+0x44400[[:space:]]+0x8000' \
    "$WORK/base-rootfs/etc/fw_env.config" || die "SD fw_env.config missing or invalid"

mkdir -p     "$WORK/base-rootfs/data/services"     "$WORK/base-rootfs/data/vpn"     "$WORK/base-rootfs/mnt/media"     "$WORK/base-rootfs/etc/wificam"

# Optional SSH is owned by WIFICAM and stays off until the marker is enabled.
if [ -e "$WORK/base-rootfs/etc/init.d/S50dropbear" ]; then
    mv "$WORK/base-rootfs/etc/init.d/S50dropbear"        "$WORK/base-rootfs/etc/init.d/K50dropbear.wificam-disabled"
fi

cat > "$WORK/base-rootfs/etc/wificam/rootfs-source.txt" <<EOF
Boot medium: SD only
SPI/NOR required: no
Base userspace: OpenIPC official T23 lite
Asset: openipc.t23-nor-lite.tgz
Asset SHA256: $OPENIPC_SHA256
Kernel: custom T23N autonomous-SD build
Kernel SHA256: $(sha256sum "$KERNEL" | awk '{print $1}')
Bootloader: T23N MMC SPL/U-Boot
Bootloader SHA256: $(sha256sum "$BOOTLOADER" | awk '{print $1}')
Branch: mymarrchWFcam
Installed: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
EOF

chmod 0755     "$WORK/base-rootfs/etc/init.d/S05peginelab-boot"     "$WORK/base-rootfs/etc/init.d/S90wificam"     "$WORK/base-rootfs/etc/init.d/S91wificam-services"     "$WORK/base-rootfs/usr/bin/wificam-camera-ctl"     "$WORK/base-rootfs/usr/bin/wificam-service-ctl"     "$WORK/base-rootfs/usr/bin/wificam-set-web-password"     "$WORK/base-rootfs/usr/share/wificam-web/cgi-bin/api"

echo "Packing complete SD rootfs..."
tar -C "$WORK/base-rootfs" -czf "$ROOTFS_TAR" .

echo
echo "Repartitioning and writing the COMPLETE autonomous SD image..."
sh "$REPO_DIR/scripts/prepare_sd.sh"     "$DEV" --yes "$BOOTLOADER" "$KERNEL" "$ROOTFS_TAR"

echo
echo "Verifying the COMPLETE autonomous SD by reading it back..."
sh "$REPO_DIR/scripts/verify_sd_firmware.sh" "$DEV" "$KERNEL" "$BOOTLOADER"

echo
echo "============================================================"
echo " T23N AUTONOMOUS SD FIRMWARE: COMPLETE + SD VERIFIED"
echo "============================================================"
echo "Boot chain:"
echo "  T23 BootROM -> SD sector 34 SPL/U-Boot"
echo "  U-Boot      -> BOOT FAT32 /uImage"
echo "  Linux       -> /dev/mmcblk0p2 ext4"
echo "  MEDIA       -> /dev/mmcblk0p3 ext4"
echo
echo "No SPI/NOR bootloader or root filesystem is required."
echo "SD verification completed successfully; the card is ready for the camera."
