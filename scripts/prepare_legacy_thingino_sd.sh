#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DEV="${1:-}"
FIRMWARE="${2:-}"
BOOTLOADER="${3:-$REPO_DIR/out/u-boot-t23n-sd.bin}"

UPSTREAM_UBOOT_SHA256="4d4d4ff27acce1e5e59577c35ef98a505ae42a0bbb07583380463a81cdbfd6a5"
UPSTREAM_UBOOT_SIZE=189685
UBOOT_SECTOR=34
FAT_START_SECTOR=2048

die() { echo "ERROR: $*" >&2; exit 1; }

[ -n "$DEV" ] || {
    echo "Usage: sudo $0 /dev/sdX [autoupdate-full.bin] [u-boot-t23n-sd.bin]" >&2
    echo "DESTROYS the selected SD card and recreates the old Thingino-style FAT32 installer layout." >&2
    exit 2
}

[ "$(id -u)" -eq 0 ] || die "run with sudo/root"
[ -b "$DEV" ] || die "not a block device: $DEV"
[ "$(lsblk -dn -o TYPE "$DEV" 2>/dev/null)" = "disk" ] || die "$DEV is not a whole disk"
[ -f "$BOOTLOADER" ] || die "bootloader not found: $BOOTLOADER"
[ -z "$FIRMWARE" ] || [ -f "$FIRMWARE" ] || die "firmware not found: $FIRMWARE"

case "$DEV" in
  /dev/sd[a-z]|/dev/mmcblk[0-9]) ;;
  *) die "refusing suspicious device name: $DEV" ;;
esac

ROOT_SRC="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
case "$ROOT_SRC" in
  "$DEV"*) die "$DEV contains the running root filesystem" ;;
esac

for cmd in blockdev lsblk sfdisk partprobe wipefs mkfs.vfat dd sha256sum mount umount sync; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd not installed"
done

SECTOR_SIZE="$(blockdev --getss "$DEV")"
[ "$SECTOR_SIZE" -eq 512 ] || die "expected 512-byte sectors, got $SECTOR_SIZE"

UBOOT_SIZE="$(wc -c < "$BOOTLOADER" | tr -d ' ')"
UBOOT_SHA="$(sha256sum "$BOOTLOADER" | awk '{print $1}')"
[ "$UBOOT_SIZE" -eq "$UPSTREAM_UBOOT_SIZE" ] || die "wrong U-Boot size: $UBOOT_SIZE != $UPSTREAM_UBOOT_SIZE"
[ "$UBOOT_SHA" = "$UPSTREAM_UBOOT_SHA256" ] || die "wrong U-Boot SHA256: $UBOOT_SHA"

echo "TARGET:"
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS "$DEV"
echo
echo "This will ERASE $DEV and create:"
echo "  MBR/DOS partition table"
echo "  p1 FAT32 starting at sector $FAT_START_SECTOR"
echo "  upstream T23N MSC0 1-bit U-Boot at raw sector $UBOOT_SECTOR"
if [ -n "$FIRMWARE" ]; then
    echo "  FAT32:/autoupdate-full.bin from: $FIRMWARE"
else
    echo "  no autoupdate file yet"
fi
echo
printf "Type LEGACY-THINGINO:%s to continue: " "$DEV"
read answer
[ "$answer" = "LEGACY-THINGINO:$DEV" ] || { echo "Cancelled."; exit 1; }

case "$DEV" in
  /dev/mmcblk*) P1="${DEV}p1" ;;
  *) P1="${DEV}1" ;;
esac

umount "$P1" 2>/dev/null || true
wipefs -a "$DEV" >/dev/null 2>&1 || true

sfdisk "$DEV" <<EOF
label: dos
unit: sectors

start=$FAT_START_SECTOR, type=0c, bootable
EOF

sync
partprobe "$DEV" 2>/dev/null || true
sleep 2
[ -b "$P1" ] || die "partition node missing: $P1"

mkfs.vfat -F 32 -n THINGINO "$P1" >/dev/null

echo "Writing U-Boot at LBA $UBOOT_SECTOR (34 * 512 = 17408 bytes / 17 KiB) ..."
dd if="$BOOTLOADER" of="$DEV" bs=512 seek="$UBOOT_SECTOR" conv=notrunc,fsync status=none

BLOCKS=$(((UBOOT_SIZE + 511) / 512))
TMP="$(mktemp)"
MNT="$(mktemp -d)"
cleanup() {
    umount "$MNT" 2>/dev/null || true
    rm -f "$TMP"
    rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

dd if="$DEV" of="$TMP" bs=512 skip="$UBOOT_SECTOR" count="$BLOCKS" status=none
READ_SHA="$(head -c "$UBOOT_SIZE" "$TMP" | sha256sum | awk '{print $1}')"
[ "$READ_SHA" = "$UBOOT_SHA" ] || die "raw U-Boot readback SHA mismatch"

START="$(lsblk -bn -o START "$P1" | tr -d ' ')"
[ "$START" = "$FAT_START_SECTOR" ] || die "p1 starts at $START, expected $FAT_START_SECTOR"

mount "$P1" "$MNT"
rm -f "$MNT/autoupdate-full.done" "$MNT/autoupdate-uboot.done" "$MNT/uenv.done"
if [ -n "$FIRMWARE" ]; then
    cp "$FIRMWARE" "$MNT/autoupdate-full.bin"
    FW_SRC_SHA="$(sha256sum "$FIRMWARE" | awk '{print $1}')"
    FW_SD_SHA="$(sha256sum "$MNT/autoupdate-full.bin" | awk '{print $1}')"
    [ "$FW_SRC_SHA" = "$FW_SD_SHA" ] || die "autoupdate-full.bin SHA mismatch after copy"
fi
sync
umount "$MNT"
sync
blockdev --flushbufs "$DEV" 2>/dev/null || true

echo
echo "LEGACY THINGINO SD PREPARED"
echo "Partition 1 start       : sector $START"
echo "Partition 1 filesystem  : FAT32"
echo "U-Boot raw start        : sector $UBOOT_SECTOR (17 KiB)"
echo "U-Boot SHA256           : $READ_SHA"
if [ -n "$FIRMWARE" ]; then
    echo "autoupdate-full.bin SHA : $FW_SD_SHA"
fi
echo
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS "$DEV"
