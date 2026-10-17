#!/bin/sh
set -eu

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
DEV="${1:-}"
KERNEL="${2:-}"

[ -n "$DEV" ] || {
    echo "Usage: sudo $0 /dev/sdX [autonomous-uImage]" >&2
    echo "Writes the COMPLETE autonomous T23N SD firmware." >&2
    exit 2
}

[ "$(id -u)" -eq 0 ] || { echo "Run with sudo/root" >&2; exit 1; }
[ -b "$DEV" ] || { echo "Not a block device: $DEV" >&2; exit 1; }
[ "$(lsblk -dn -o TYPE "$DEV" 2>/dev/null)" = "disk" ] || {
    echo "$DEV is not a whole disk" >&2
    exit 1
}

ROOT_SRC="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
case "$ROOT_SRC" in
  "$DEV"*) echo "REFUSING: $DEV contains the running root filesystem" >&2; exit 1 ;;
esac

echo "Autonomous SD mode: the camera's SPI/NOR boot flash is not required."
echo "The full flasher will reserve raw sectors for T23 BootROM/SPL/U-Boot/kernel,"
echo "then create BOOT, ROOTFS and MEDIA partitions."
echo
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS "$DEV"
echo

if [ -n "$KERNEL" ]; then
    exec sh "$HERE/flash_full_firmware_sd.sh" "$DEV" "$KERNEL"
else
    exec sh "$HERE/flash_full_firmware_sd.sh" "$DEV"
fi
