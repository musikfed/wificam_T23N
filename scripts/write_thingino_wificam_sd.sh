#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DEV="${1:-}"
IMAGE="${2:-$REPO_DIR/Thingino/thingino-t23-sd.bin}"

die() { echo "ERROR: $*" >&2; exit 1; }

[ -n "$DEV" ] || {
    echo "Usage: sudo $0 /dev/sdX [Thingino/thingino-t23-sd.bin]" >&2
    exit 2
}

[ "$(id -u)" -eq 0 ] || die "run with sudo/root"
[ -b "$DEV" ] || die "not a block device: $DEV"
[ -f "$IMAGE" ] || die "image not found: $IMAGE"
[ "$(lsblk -dn -o TYPE "$DEV" 2>/dev/null)" = "disk" ] || die "$DEV is not a whole disk"

case "$DEV" in
  /dev/sd[a-z]|/dev/mmcblk[0-9]) ;;
  *) die "refusing suspicious device name: $DEV" ;;
esac

ROOT_SRC="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
case "$ROOT_SRC" in
  "$DEV"*) die "$DEV contains the running root filesystem" ;;
esac

RM="$(lsblk -dn -o RM "$DEV" | tr -d ' ')"
TRAN="$(lsblk -dn -o TRAN "$DEV" | tr -d ' ')"
[ "$RM" = "1" ] || die "$DEV is not removable (RM=$RM)"
[ "$TRAN" = "usb" ] || die "$DEV is not the USB card reader (TRAN=$TRAN)"

for cmd in dd head sha256sum lsblk blockdev partprobe od sync; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd not installed"
done

SECTOR_SIZE="$(blockdev --getss "$DEV")"
[ "$SECTOR_SIZE" -eq 512 ] || die "expected 512-byte sectors, got $SECTOR_SIZE"

IMAGE_SIZE="$(stat -c '%s' "$IMAGE")"
DEV_SIZE="$(blockdev --getsize64 "$DEV")"
[ "$IMAGE_SIZE" -lt "$DEV_SIZE" ] || die "image does not fit on target"
IMAGE_SHA="$(sha256sum "$IMAGE" | awk '{print $1}')"

echo "TARGET:"
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS "$DEV"
echo
echo "IMAGE:"
echo "  $IMAGE"
echo "  size   : $IMAGE_SIZE bytes"
echo "  SHA256 : $IMAGE_SHA"
echo
echo "This writes the complete Thingino MMC SD image:"
echo "  sector 0       : INGE + DOS/MBR partition table"
echo "  sector 34      : SPL/MSPL"
echo "  sector 86      : U-Boot proper"
echo "  p1 @ 1 MiB     : FAT32 /uImage"
echo "  p2 @ 17 MiB    : ext4 rootfs with PegineLab WIFICAM"
echo "  Web UI         : http://CAMERA_IP:8080/"
echo
printf "Type THINGINO-WIFICAM:%s to continue: " "$DEV"
read answer
[ "$answer" = "THINGINO-WIFICAM:$DEV" ] || { echo "Cancelled."; exit 1; }

lsblk -ln -o PATH "$DEV" | tail -n +2 | while IFS= read -r p; do
    [ -n "$p" ] && umount "$p" 2>/dev/null || true
done

dd if="$IMAGE" of="$DEV" bs=4M conv=fsync status=progress
sync
blockdev --flushbufs "$DEV" 2>/dev/null || true

READ_SHA="$(head -c "$IMAGE_SIZE" "$DEV" | sha256sum | awk '{print $1}')"
[ "$READ_SHA" = "$IMAGE_SHA" ] || die "full image readback SHA mismatch"

INGE="$(dd if="$DEV" bs=1 count=4 status=none 2>/dev/null)"
[ "$INGE" = "INGE" ] || die "INGE header missing at byte 0"

MSPL="$(dd if="$DEV" bs=512 skip=34 count=1 status=none | od -An -tx4 -N4 | tr -d ' \n')"
[ "$MSPL" = "4d53504c" ] || die "MSPL magic missing at LBA34: $MSPL"

MBR_SIG="$(dd if="$DEV" bs=1 skip=510 count=2 status=none | od -An -tx1 | tr -d ' \n')"
[ "$MBR_SIG" = "55aa" ] || die "MBR signature missing: $MBR_SIG"

partprobe "$DEV" 2>/dev/null || true
sleep 2

case "$DEV" in
  /dev/mmcblk*) P1="${DEV}p1"; P2="${DEV}p2" ;;
  *) P1="${DEV}1"; P2="${DEV}2" ;;
esac

[ -b "$P1" ] || die "BOOT partition missing after write: $P1"
[ -b "$P2" ] || die "ROOTFS partition missing after write: $P2"

P1_START="$(lsblk -bn -o START "$P1" | tr -d ' ')"
P2_START="$(lsblk -bn -o START "$P2" | tr -d ' ')"
[ "$P1_START" = "2048" ] || die "p1 starts at $P1_START, expected 2048"
[ "$P2_START" = "34816" ] || die "p2 starts at $P2_START, expected 34816 (17 MiB)"

echo
echo "THINGINO WIFICAM SD WRITE: VERIFIED"
echo "Full readback SHA256 : $READ_SHA"
echo "Header byte 0       : INGE"
echo "MBR signature       : $MBR_SIG"
echo "LBA34 MSPL magic    : $MSPL"
echo "p1 start            : sector $P1_START"
echo "p2 start            : sector $P2_START"
echo
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS "$DEV"
echo
echo "The remaining card capacity is intentionally untouched for now."
echo "First prove hardware boot + PegineLab WIFICAM, then expand/create MEDIA."
