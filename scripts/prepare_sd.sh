#!/bin/sh
set -eu

usage() {
    echo "Usage: sudo $0 /dev/sdX --yes [uImage] [rootfs-overlay.tar.gz]"
    echo "DESTROYS ALL DATA on the selected device."
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

echo "WARNING: ALL DATA ON $DEV WILL BE DESTROYED"
lsblk "$DEV"
sleep 2

for n in 1 2 3 4; do
    umount "$(part "$n")" 2>/dev/null || true
done

wipefs -a "$DEV"
sfdisk "$DEV" <<'EOF'
label: dos
unit: MiB

start=1,   size=128, type=c, bootable
           size=1024, type=83
           size=256, type=83
                       type=83
EOF

sync
partprobe "$DEV" 2>/dev/null || true
sleep 2

mkfs.vfat -F 32 -n BOOT "$(part 1)"
mkfs.ext4 -F -L ROOTFS "$(part 2)"
mkfs.ext4 -F -L DATA "$(part 3)"
mkfs.ext4 -F -L RECORDINGS "$(part 4)"

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
    sync
    umount "$MNT"
fi

echo
echo "SD card prepared:"
lsblk -f "$DEV"
echo
echo "Next: validate U-Boot printenv and load uImage from BOOT into RAM."
echo "Do NOT erase the factory SPI/NOR/NAND yet."
