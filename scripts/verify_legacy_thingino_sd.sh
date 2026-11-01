#!/bin/sh
set -eu

DEV="${1:-}"
EXPECTED_PAYLOAD="${2:-}"

UPSTREAM_UBOOT_SHA256="4d4d4ff27acce1e5e59577c35ef98a505ae42a0bbb07583380463a81cdbfd6a5"
UPSTREAM_UBOOT_SIZE=189685
UBOOT_SECTOR=34
FAT_START_SECTOR=2048
FAT_SIZE_SECTORS=262144

die() { echo "ERROR: $*" >&2; exit 1; }

[ -n "$DEV" ] || {
    echo "Usage: sudo $0 /dev/sdX [expected-autoupdate-full.bin]" >&2
    exit 2
}

[ "$(id -u)" -eq 0 ] || die "run with sudo/root"
[ -b "$DEV" ] || die "not a block device: $DEV"
[ "$(lsblk -dn -o TYPE "$DEV" 2>/dev/null)" = "disk" ] || die "$DEV is not a whole disk"
[ -z "$EXPECTED_PAYLOAD" ] || [ -f "$EXPECTED_PAYLOAD" ] || die "expected payload not found: $EXPECTED_PAYLOAD"

case "$DEV" in
  /dev/sd[a-z]|/dev/mmcblk[0-9]) ;;
  *) die "refusing suspicious device name: $DEV" ;;
esac

for cmd in blockdev lsblk dd od sha256sum head mount umount findmnt wc awk tr; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd not installed"
done

SECTOR_SIZE="$(blockdev --getss "$DEV")"
[ "$SECTOR_SIZE" -eq 512 ] || die "expected 512-byte sectors, got $SECTOR_SIZE"

case "$DEV" in
  /dev/mmcblk*) P1="${DEV}p1" ;;
  *) P1="${DEV}1" ;;
esac

[ -b "$P1" ] || die "partition 1 missing: $P1"
[ "$(lsblk -dn -o FSTYPE "$P1" 2>/dev/null)" = "vfat" ] || die "$P1 is not FAT/vfat"

START="$(lsblk -bn -o START "$P1" | tr -d ' ')"
SIZE_SECTORS="$(blockdev --getsz "$P1")"
[ "$START" = "$FAT_START_SECTOR" ] || die "p1 starts at $START, expected $FAT_START_SECTOR"
[ "$SIZE_SECTORS" = "$FAT_SIZE_SECTORS" ] || die "p1 size is $SIZE_SECTORS sectors, expected $FAT_SIZE_SECTORS"

MBR_SIG="$(dd if="$DEV" bs=1 skip=510 count=2 status=none | od -An -tx1 | tr -d ' \n')"
[ "$MBR_SIG" = "55aa" ] || die "DOS/MBR signature missing: $MBR_SIG"

MAGIC="$(dd if="$DEV" bs=512 skip="$UBOOT_SECTOR" count=1 status=none | od -An -tx4 -N4 | tr -d ' \n')"
[ "$MAGIC" = "4d53504c" ] || die "MSPL magic missing at LBA $UBOOT_SECTOR: $MAGIC"

UBOOT_BLOCKS=$(((UPSTREAM_UBOOT_SIZE + 511) / 512))
UBOOT_END_SECTOR=$((UBOOT_SECTOR + UBOOT_BLOCKS - 1))
TMP="$(mktemp)"
MNT="$(mktemp -d)"

cleanup() {
    umount "$MNT" 2>/dev/null || true
    rm -f "$TMP"
    rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

dd if="$DEV" of="$TMP" bs=512 skip="$UBOOT_SECTOR" count="$UBOOT_BLOCKS" status=none
READ_SHA="$(head -c "$UPSTREAM_UBOOT_SIZE" "$TMP" | sha256sum | awk '{print $1}')"
[ "$READ_SHA" = "$UPSTREAM_UBOOT_SHA256" ] || die "raw U-Boot SHA mismatch: $READ_SHA"

EXISTING_MOUNT="$(findmnt -n -o TARGET "$P1" 2>/dev/null || true)"
if [ -n "$EXISTING_MOUNT" ]; then
    MOUNT_POINT="$EXISTING_MOUNT"
    OWN_MOUNT=0
else
    mount -o ro "$P1" "$MNT"
    MOUNT_POINT="$MNT"
    OWN_MOUNT=1
fi

PAYLOAD="$MOUNT_POINT/autoupdate-full.bin"
if [ -f "$PAYLOAD" ]; then
    PAYLOAD_SIZE="$(wc -c < "$PAYLOAD" | tr -d ' ')"
    PAYLOAD_SHA="$(sha256sum "$PAYLOAD" | awk '{print $1}')"
    [ "$PAYLOAD_SIZE" -gt 0 ] || die "BOOT:/autoupdate-full.bin is empty"

    if [ -n "$EXPECTED_PAYLOAD" ]; then
        EXPECTED_SHA="$(sha256sum "$EXPECTED_PAYLOAD" | awk '{print $1}')"
        [ "$PAYLOAD_SHA" = "$EXPECTED_SHA" ] || die "autoupdate-full.bin SHA mismatch: SD=$PAYLOAD_SHA expected=$EXPECTED_SHA"
    fi
    PAYLOAD_STATUS="PRESENT"
else
    PAYLOAD_STATUS="NOT PRESENT"
    PAYLOAD_SIZE="-"
    PAYLOAD_SHA="-"
fi

if [ "$OWN_MOUNT" -eq 1 ]; then
    umount "$MNT"
fi

echo
echo "LEGACY THINGINO RECOVERY SD: VERIFIED"
echo "MBR signature            : $MBR_SIG"
echo "Raw MSPL magic           : $MAGIC"
echo "Raw U-Boot sector span   : $UBOOT_SECTOR..$UBOOT_END_SECTOR"
echo "Raw U-Boot SHA256        : $READ_SHA"
echo "BOOT partition start     : sector $START"
echo "BOOT partition size      : 128 MiB"
echo "BOOT filesystem          : FAT32"
echo "autoupdate-full.bin      : $PAYLOAD_STATUS"
echo "autoupdate size          : $PAYLOAD_SIZE"
echo "autoupdate SHA256        : $PAYLOAD_SHA"
echo
echo "NOTE: this verifier checks ONLY the one-partition legacy/recovery layout."
echo "Do not use scripts/verify_sd_firmware.sh for this card; that verifier expects p2/p3 and /uImage."
