#!/bin/sh
set -eu

DEV="${1:-}"
IMAGE="${2:-}"

die() { echo "ERROR: $*" >&2; exit 1; }

[ -n "$DEV" ] && [ -n "$IMAGE" ] || {
    echo "Usage: sudo $0 /dev/sdX uImage" >&2
    exit 2
}
[ "$(id -u)" -eq 0 ] || die "run with sudo/root"
[ -b "$DEV" ] || die "not a block device: $DEV"
[ -f "$IMAGE" ] || die "kernel image not found: $IMAGE"
[ "$(lsblk -dn -o TYPE "$DEV" 2>/dev/null)" = "disk" ] || die "$DEV is not a whole disk"

case "$DEV" in
  /dev/sd[a-z]|/dev/mmcblk[0-9]) ;;
  *) die "refusing suspicious device name: $DEV" ;;
esac

SECTOR_SIZE="$(blockdev --getss "$DEV")"
[ "$SECTOR_SIZE" -eq 512 ] || die "expected 512-byte sectors, got $SECTOR_SIZE"

part() {
    case "$DEV" in
      /dev/mmcblk*) echo "${DEV}p$1" ;;
      *) echo "${DEV}$1" ;;
    esac
}

P1="$(part 1)"
P2="$(part 2)"
P3="$(part 3)"
[ -b "$P1" ] && [ -b "$P2" ] && [ -b "$P3" ] || die "partition nodes are missing"

# Partition map expected by the autonomous no-SPI/NOR layout.
P1_START="$(lsblk -bn -o START "$P1" | tr -d ' ')"
[ "$P1_START" = "32768" ] || die "BOOT does not start at sector 32768 (16 MiB): $P1_START"

P1_LABEL="$(lsblk -no LABEL "$P1" | xargs)"
P2_LABEL="$(lsblk -no LABEL "$P2" | xargs)"
P3_LABEL="$(lsblk -no LABEL "$P3" | xargs)"
[ "$P1_LABEL" = "BOOT" ] || die "p1 label is not BOOT"
[ "$P2_LABEL" = "ROOTFS" ] || die "p2 label is not ROOTFS"
[ "$P3_LABEL" = "MEDIA" ] || die "p3 label is not MEDIA"

# BootROM-visible MMC SPL magic at raw sector 34.
MAGIC="$(dd if="$DEV" bs=512 skip=34 count=1 status=none | od -An -tx4 -N4 | tr -d ' \n')"
[ "$MAGIC" = "4d53504c" ] || die "SPL magic mismatch at sector 34: $MAGIC"

IMAGE_REAL="$(readlink -f "$IMAGE")"
KERNEL_SIZE="$(wc -c < "$IMAGE_REAL" | tr -d ' ')"
KERNEL_BLOCKS=$(((KERNEL_SIZE + 511) / 512))
SOURCE_SHA="$(sha256sum "$IMAGE_REAL" | awk '{print $1}')"

TMP="$(mktemp)"
MNT="$(mktemp -d)"
cleanup() {
    umount "$MNT" 2>/dev/null || true
    rm -f "$TMP"
    rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

sync
blockdev --flushbufs "$DEV" 2>/dev/null || true

# Verify the complete raw kernel payload at sector 0x1800.
dd if="$DEV" of="$TMP" bs=512 skip=$((0x1800)) count="$KERNEL_BLOCKS" iflag=direct status=none 2>/dev/null || dd if="$DEV" of="$TMP" bs=512 skip=$((0x1800)) count="$KERNEL_BLOCKS" status=none
SD_SHA="$(head -c "$KERNEL_SIZE" "$TMP" | sha256sum | awk '{print $1}')"
[ "$SOURCE_SHA" = "$SD_SHA" ] || die "raw kernel SHA mismatch: source=$SOURCE_SHA sd=$SD_SHA"

mount -o ro "$P1" "$MNT"
[ -f "$MNT/uImage" ] || die "BOOT/uImage missing"
[ -f "$MNT/u-boot-t23n-sd.bin" ] || die "BOOT/u-boot-t23n-sd.bin missing"
BOOT_KERNEL_SHA="$(sha256sum "$MNT/uImage" | awk '{print $1}')"
[ "$SOURCE_SHA" = "$BOOT_KERNEL_SHA" ] || die "BOOT/uImage SHA mismatch"
umount "$MNT"

mount -o ro "$P2" "$MNT"
[ -x "$MNT/bin/sh" ] || die "ROOTFS /bin/sh missing"
[ -x "$MNT/init" ] || die "ROOTFS /init missing"
[ -f "$MNT/etc/fw_env.config" ] || die "ROOTFS /etc/fw_env.config missing"
grep -Eq '^/dev/mmcblk0[[:space:]]+0x40400[[:space:]]+0x8000' "$MNT/etc/fw_env.config" ||     die "ROOTFS fw_env.config is invalid"
[ -x "$MNT/etc/init.d/S90wificam" ] || die "WIFICAM init script missing"
[ -x "$MNT/etc/init.d/S91wificam-services" ] || die "WIFICAM services init script missing"
umount "$MNT"

mount -o ro "$P3" "$MNT"
[ -d "$MNT/recordings" ] || die "MEDIA/recordings missing"
[ -d "$MNT/snapshots" ] || die "MEDIA/snapshots missing"
[ -d "$MNT/events" ] || die "MEDIA/events missing"
umount "$MNT"

echo
echo "SD FIRMWARE VERIFY: OK"
echo "SPL magic           : $MAGIC"
echo "Raw kernel SHA256   : $SD_SHA"
echo "BOOT uImage SHA256  : $BOOT_KERNEL_SHA"
echo "ROOTFS              : OK"
echo "MEDIA               : OK"
echo
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS "$DEV"
