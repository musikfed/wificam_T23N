#!/bin/sh
set -eu

MEDIA_GIB="${MEDIA_GIB:-20}"
BOOT_MIB=128
MEDIA_MIB=$((MEDIA_GIB * 1024))
RESERVE_MIB=8
MIN_ROOTFS_MIB=2048

usage() {
    echo "Usage: sudo $0 /dev/sdX --yes [uImage] [FULL-rootfs.tar.gz]"
    echo "DESTROYS ALL DATA on the selected device."
    echo "Layout: BOOT 128 MiB + ROOTFS all remaining space + MEDIA ${MEDIA_GIB} GiB."
    echo "The rootfs archive must be a COMPLETE bootable userspace."
    exit 2
}

[ "$#" -ge 2 ] || usage
DEV="$1"
CONFIRM="$2"
IMAGE="${3:-}"
ROOTFS_TAR="${4:-}"

[ "$CONFIRM" = "--yes" ] || usage
[ -b "$DEV" ] || { echo "Not a block device: $DEV" >&2; exit 1; }

case "$DEV" in
  /dev/sd[a-z]|/dev/mmcblk[0-9]) ;;
  *) echo "Refusing suspicious device name: $DEV" >&2; exit 1 ;;
esac

ROOT_SRC="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
case "$ROOT_SRC" in
  "$DEV"*) echo "REFUSING: $DEV contains the running root filesystem" >&2; exit 1 ;;
esac

part() {
    case "$DEV" in
      /dev/mmcblk*) echo "${DEV}p$1" ;;
      *) echo "${DEV}$1" ;;
    esac
}

BYTES="$(blockdev --getsize64 "$DEV")"
TOTAL_MIB=$((BYTES / 1024 / 1024))
ROOTFS_MIB=$((TOTAL_MIB - 1 - BOOT_MIB - MEDIA_MIB - RESERVE_MIB))

[ "$ROOTFS_MIB" -ge "$MIN_ROOTFS_MIB" ] || {
    echo "REFUSING: card is too small." >&2
    echo "Total: ${TOTAL_MIB} MiB; requested MEDIA: ${MEDIA_MIB} MiB; ROOTFS would be only ${ROOTFS_MIB} MiB." >&2
    exit 1
}

echo "WARNING: ALL DATA ON $DEV WILL BE DESTROYED"
echo
echo "Planned layout:"
echo "  BOOT   : ${BOOT_MIB} MiB FAT32"
echo "  ROOTFS : ${ROOTFS_MIB} MiB ext4"
echo "  MEDIA  : ${MEDIA_MIB} MiB ext4 (${MEDIA_GIB} GiB)"
echo
lsblk "$DEV"
sleep 2

for n in 1 2 3; do
    umount "$(part "$n")" 2>/dev/null || true
done

wipefs -a "$DEV"

sfdisk "$DEV" <<EOF
label: dos
unit: MiB

start=1, size=$BOOT_MIB, type=c, bootable
         size=$ROOTFS_MIB, type=83
         size=$MEDIA_MIB, type=83
EOF

sync
partprobe "$DEV" 2>/dev/null || true
sleep 2

mkfs.vfat -F 32 -n BOOT "$(part 1)"
mkfs.ext4 -F -L ROOTFS "$(part 2)"
mkfs.ext4 -F -L MEDIA "$(part 3)"

MNT="$(mktemp -d)"
trap 'umount "$MNT" 2>/dev/null || true; rmdir "$MNT" 2>/dev/null || true' EXIT

if [ -n "$IMAGE" ]; then
    [ -f "$IMAGE" ] || { echo "uImage not found: $IMAGE" >&2; exit 1; }
    mount "$(part 1)" "$MNT"
    cp "$IMAGE" "$MNT/uImage"
    sync
    umount "$MNT"
fi

if [ -n "$ROOTFS_TAR" ]; then
    [ -f "$ROOTFS_TAR" ] || { echo "rootfs archive not found: $ROOTFS_TAR" >&2; exit 1; }
    mount "$(part 2)" "$MNT"
    tar -C "$MNT" -xzf "$ROOTFS_TAR"
    [ -x "$MNT/bin/sh" ] || {
        umount "$MNT"
        echo "REFUSING: archive does not look like a complete rootfs (/bin/sh missing)" >&2
        exit 1
    }
    mkdir -p "$MNT/data" "$MNT/mnt/media"
    sync
    umount "$MNT"
fi

mount "$(part 3)" "$MNT"
mkdir -p "$MNT/recordings" "$MNT/snapshots" "$MNT/events"
sync
umount "$MNT"

echo
echo "SD card prepared:"
lsblk -f "$DEV"
echo
echo "MEDIA contains: recordings/ snapshots/ events/"
echo "ROOTFS gets every remaining MiB outside BOOT and MEDIA."
echo "Next: validate U-Boot printenv and load uImage from BOOT into RAM."
echo "Do NOT erase the factory SPI/NOR/NAND yet."
