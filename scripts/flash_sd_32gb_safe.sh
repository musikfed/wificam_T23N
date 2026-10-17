#!/bin/sh
set -eu

# Extra safety wrapper for the common 32 GB card workflow.
# Actual layout/writing is performed by prepare_sd.sh.

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
DEV="${1:-}"
KERNEL="${2:-$HOME/myipcam/build/kernel/arch/mips/boot/uImage}"
ROOTFS="${3:-}"

[ -n "$DEV" ] || {
  echo "Usage: sudo $0 /dev/sdX [uImage] [wificam-rootfs.tar.gz]" >&2
  exit 2
}
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo/root" >&2; exit 1; }
[ -b "$DEV" ] || { echo "Not a block device: $DEV" >&2; exit 1; }
[ "$(lsblk -dn -o TYPE "$DEV" 2>/dev/null)" = "disk" ] || { echo "$DEV is not a whole disk" >&2; exit 1; }

ROOT_SRC="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
case "$ROOT_SRC" in "$DEV"*) echo "REFUSING: $DEV contains the running root filesystem" >&2; exit 1;; esac

echo "Windows screenshot reference: SD was Disk 2, removable, 29.12 GB, RAW."
echo "Linux device names are independent from Windows Disk numbers."
echo
lsblk -o NAME,PATH,SIZE,MODEL,TRAN,RM,FSTYPE,MOUNTPOINTS "$DEV"
echo
printf "Type the exact Linux device path (%s) to ERASE it: " "$DEV"
read confirm
[ "$confirm" = "$DEV" ] || { echo "Cancelled."; exit 1; }

if [ -n "$ROOTFS" ]; then
  exec "$HERE/prepare_sd.sh" "$DEV" --yes "$KERNEL" "$ROOTFS"
else
  exec "$HERE/prepare_sd.sh" "$DEV" --yes "$KERNEL"
fi
