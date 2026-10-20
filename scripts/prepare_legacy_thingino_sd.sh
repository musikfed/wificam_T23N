#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DEV="${1:-}"
FIRMWARE="${2:-}"
BOOTLOADER="${3:-$REPO_DIR/out/u-boot-t23n-sd.bin}"

UPSTREAM_UBOOT_SHA256="4d4d4ff27acce1e5e59577c35ef98a505ae42a0bbb07583380463a81cdbfd6a5"
UPSTREAM_UBOOT_SIZE=189685

# Reproduce the historically working Thingino SD installer geometry first.
UBOOT_SECTOR=34
FAT_START_SECTOR=2048
FAT_SIZE_MIB=128
SECTORS_PER_MIB=2048
FAT_SIZE_SECTORS=$((FAT_SIZE_MIB * SECTORS_PER_MIB))

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
    echo "Usage: sudo $0 /dev/sdX [autoupdate-full.bin] [u-boot-t23n-sd.bin]" >&2
    echo "DESTROYS the selected SD card." >&2
    echo "Creates ONLY one 128 MiB FAT32 BOOT partition at LBA 2048." >&2
    echo "Writes the exact T23N MSC0 1-bit SPL/U-Boot raw at LBA 34." >&2
    echo "The rest of the card is intentionally left UNALLOCATED for this recovery test." >&2
    exit 2
}

[ -n "$DEV" ] || usage
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

for cmd in blockdev lsblk sfdisk partprobe wipefs mkfs.vfat dd od sha256sum mount umount sync head wc awk tr; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd not installed"
done

SECTOR_SIZE="$(blockdev --getss "$DEV")"
[ "$SECTOR_SIZE" -eq 512 ] || die "expected 512-byte sectors, got $SECTOR_SIZE"
TOTAL_SECTORS="$(blockdev --getsz "$DEV")"
MIN_SECTORS=$((FAT_START_SECTOR + FAT_SIZE_SECTORS))
[ "$TOTAL_SECTORS" -gt "$MIN_SECTORS" ] || die "card too small for 128 MiB BOOT partition"

UBOOT_SIZE="$(wc -c < "$BOOTLOADER" | tr -d ' ')"
UBOOT_SHA="$(sha256sum "$BOOTLOADER" | awk '{print $1}')"
[ "$UBOOT_SIZE" -eq "$UPSTREAM_UBOOT_SIZE" ] || die "wrong U-Boot size: $UBOOT_SIZE != $UPSTREAM_UBOOT_SIZE"
[ "$UBOOT_SHA" = "$UPSTREAM_UBOOT_SHA256" ] || die "wrong U-Boot SHA256: $UBOOT_SHA"

UBOOT_BLOCKS=$(((UBOOT_SIZE + 511) / 512))
UBOOT_END_SECTOR=$((UBOOT_SECTOR + UBOOT_BLOCKS - 1))
[ "$UBOOT_END_SECTOR" -lt "$FAT_START_SECTOR" ] || die "raw U-Boot would overlap BOOT partition"

case "$DEV" in
  /dev/mmcblk*) P1="${DEV}p1" ;;
  *) P1="${DEV}1" ;;
esac

echo "TARGET:"
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS "$DEV"
echo
echo "RECOVERY/KNOWN-WORKING GEOMETRY:"
echo "  sector 0             : DOS/MBR"
echo "  sector $UBOOT_SECTOR..$UBOOT_END_SECTOR    : raw T23N MSC0 1-bit SPL/U-Boot"
echo "  sector $FAT_START_SECTOR          : p1 BOOT FAT32"
echo "  p1 size              : $FAT_SIZE_MIB MiB"
echo "  after p1             : UNALLOCATED (no p2/p3 yet)"
if [ -n "$FIRMWARE" ]; then
    echo "  BOOT:/autoupdate-full.bin : $FIRMWARE"
else
    echo "  BOOT:/autoupdate-full.bin : NOT PROVIDED"
fi
echo
printf "Type LEGACY-THINGINO:%s to continue: " "$DEV"
read answer
[ "$answer" = "LEGACY-THINGINO:$DEV" ] || { echo "Cancelled."; exit 1; }

# Unmount any old partitions that may still exist before rewriting the map.
lsblk -ln -o PATH "$DEV" | tail -n +2 | while IFS= read -r p; do
    [ -n "$p" ] && umount "$p" 2>/dev/null || true
done

# Remove the previous partition map/bootstrap area. Old filesystem signatures
# farther into the card are harmless because that area stays unallocated here.
dd if=/dev/zero of="$DEV" bs=1M count=1 conv=fsync status=none
wipefs -a "$DEV" >/dev/null 2>&1 || true

# Only one small FAT32 partition. Do not create ROOTFS/MEDIA at this stage.
sfdisk "$DEV" <<EOF
label: dos
unit: sectors

start=$FAT_START_SECTOR, size=$FAT_SIZE_SECTORS, type=0c, bootable
EOF

sync
partprobe "$DEV" 2>/dev/null || true
sleep 2
[ -b "$P1" ] || die "partition node missing: $P1"

mkfs.vfat -F 32 -n BOOT "$P1" >/dev/null

# IMPORTANT: raw bootloader is written AFTER partitioning and formatting.
echo "Writing exact U-Boot raw at LBA $UBOOT_SECTOR (17 KiB) ..."
dd if="$BOOTLOADER" of="$DEV" bs=512 seek="$UBOOT_SECTOR" conv=notrunc,fsync status=none

TMP="$(mktemp)"
MNT="$(mktemp -d)"
cleanup() {
    umount "$MNT" 2>/dev/null || true
    rm -f "$TMP"
    rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Verify partition geometry.
START="$(lsblk -bn -o START "$P1" | tr -d ' ')"
SIZE_SECTORS="$(blockdev --getsz "$P1")"
[ "$START" = "$FAT_START_SECTOR" ] || die "p1 starts at $START, expected $FAT_START_SECTOR"
[ "$SIZE_SECTORS" = "$FAT_SIZE_SECTORS" ] || die "p1 size is $SIZE_SECTORS sectors, expected $FAT_SIZE_SECTORS"

MBR_SIG="$(dd if="$DEV" bs=1 skip=510 count=2 status=none | od -An -tx1 | tr -d ' \n')"
[ "$MBR_SIG" = "55aa" ] || die "DOS/MBR signature missing"

MAGIC="$(dd if="$DEV" bs=512 skip="$UBOOT_SECTOR" count=1 status=none | od -An -tx4 -N4 | tr -d ' \n')"
[ "$MAGIC" = "4d53504c" ] || die "MSPL magic missing at LBA $UBOOT_SECTOR: $MAGIC"

# Verify every byte of the bootloader after it was written to the raw SD area.
dd if="$DEV" of="$TMP" bs=512 skip="$UBOOT_SECTOR" count="$UBOOT_BLOCKS" status=none
READ_SHA="$(head -c "$UBOOT_SIZE" "$TMP" | sha256sum | awk '{print $1}')"
[ "$READ_SHA" = "$UBOOT_SHA" ] || die "raw U-Boot readback SHA mismatch"

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
echo "LEGACY THINGINO RECOVERY SD: VERIFIED"
echo "MBR signature            : $MBR_SIG"
echo "Raw MSPL magic           : $MAGIC"
echo "Raw U-Boot sector span   : $UBOOT_SECTOR..$UBOOT_END_SECTOR"
echo "Raw U-Boot SHA256        : $READ_SHA"
echo "BOOT partition start     : sector $START"
echo "BOOT partition size      : $FAT_SIZE_MIB MiB"
echo "BOOT filesystem          : FAT32"
echo "Remaining card space     : intentionally UNALLOCATED"
if [ -n "$FIRMWARE" ]; then
    echo "autoupdate-full.bin SHA  : $FW_SD_SHA"
else
    echo "autoupdate-full.bin      : NOT PRESENT"
fi
echo
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS "$DEV"
