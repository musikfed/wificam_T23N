#!/bin/sh
set -eu

DEV="${1:-}"
BOOTLOADER="${2:-}"
CONFIRM="${3:-}"

SD_UBOOT_SECTOR=34
SD_UBOOT_ENV_SECTOR=514

die() { echo "ERROR: $*" >&2; exit 1; }

[ -n "$DEV" ] && [ -n "$BOOTLOADER" ] || {
    echo "Usage: sudo $0 /dev/sdX u-boot-t23n-sd.bin [--yes]" >&2
    exit 2
}
[ "$(id -u)" -eq 0 ] || die "run with sudo/root"
[ -b "$DEV" ] || die "not a block device: $DEV"
[ -f "$BOOTLOADER" ] || die "bootloader not found: $BOOTLOADER"
[ "$(lsblk -dn -o TYPE "$DEV" 2>/dev/null)" = "disk" ] || die "$DEV is not a whole disk"

case "$DEV" in
  /dev/sd[a-z]|/dev/mmcblk[0-9]) ;;
  *) die "refusing suspicious device name: $DEV" ;;
esac

SECTOR_SIZE="$(blockdev --getss "$DEV")"
[ "$SECTOR_SIZE" -eq 512 ] || die "expected 512-byte sectors, got $SECTOR_SIZE"

SOURCE_MAGIC="$(od -An -tx4 -N4 "$BOOTLOADER" | tr -d ' \n')"
[ "$SOURCE_MAGIC" = "4d53504c" ] || die "source is not a T23 MMC SPL image (magic=$SOURCE_MAGIC)"

SIZE="$(wc -c < "$BOOTLOADER" | tr -d ' ')"
BLOCKS=$(((SIZE + 511) / 512))
MAX_BYTES=$(((SD_UBOOT_ENV_SECTOR - SD_UBOOT_SECTOR) * 512))
[ "$SIZE" -le "$MAX_BYTES" ] || die "bootloader overlaps environment area"

if [ "$CONFIRM" != "--yes" ]; then
    echo "Target: $DEV"
    lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS "$DEV"
    echo "Bootloader bytes : $SIZE"
    echo "Raw start        : sector $SD_UBOOT_SECTOR"
    printf "Type RAW-UBOOT:%s to rewrite only SPL/U-Boot: " "$DEV"
    read answer
    [ "$answer" = "RAW-UBOOT:$DEV" ] || { echo "Cancelled."; exit 1; }
fi

PAD="$(mktemp)"
READBACK="$(mktemp)"
MNT="$(mktemp -d)"
cleanup() {
    umount "$MNT" 2>/dev/null || true
    rm -f "$PAD" "$READBACK"
    rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

cp "$BOOTLOADER" "$PAD"
truncate -s $((BLOCKS * 512)) "$PAD"
SOURCE_SHA="$(sha256sum "$BOOTLOADER" | awk '{print $1}')"

echo "Writing T23N MSC0 1-bit SPL/U-Boot at sector $SD_UBOOT_SECTOR ..."
if ! dd if="$PAD" of="$DEV" bs=512 seek="$SD_UBOOT_SECTOR" count="$BLOCKS" oflag=direct conv=notrunc,fsync status=none 2>/dev/null; then
    dd if="$PAD" of="$DEV" bs=512 seek="$SD_UBOOT_SECTOR" count="$BLOCKS" conv=notrunc,fsync status=none
fi
sync
blockdev --flushbufs "$DEV" 2>/dev/null || true
sleep 2

if ! dd if="$DEV" of="$READBACK" bs=512 skip="$SD_UBOOT_SECTOR" count="$BLOCKS" iflag=direct status=none 2>/dev/null; then
    dd if="$DEV" of="$READBACK" bs=512 skip="$SD_UBOOT_SECTOR" count="$BLOCKS" status=none
fi
SD_SHA="$(head -c "$SIZE" "$READBACK" | sha256sum | awk '{print $1}')"
DISK_MAGIC="$(od -An -tx4 -N4 "$READBACK" | tr -d ' \n')"

echo "Bootloader source SHA256 : $SOURCE_SHA"
echo "Bootloader SD SHA256     : $SD_SHA"
echo "SPL magic                : $DISK_MAGIC"

[ "$SOURCE_SHA" = "$SD_SHA" ] || die "raw SPL/U-Boot SHA mismatch"
[ "$DISK_MAGIC" = "4d53504c" ] || die "raw SPL magic mismatch"

case "$DEV" in
  /dev/mmcblk*) P1="${DEV}p1" ;;
  *) P1="${DEV}1" ;;
esac
[ -b "$P1" ] || die "BOOT partition missing: $P1"

mount "$P1" "$MNT"
cp "$BOOTLOADER" "$MNT/u-boot-t23n-sd.bin"
sync
umount "$MNT"

echo "Raw SPL/U-Boot readback  : OK"
echo "BOOT partition copy      : updated"
