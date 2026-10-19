#!/bin/sh
set -eu

DEV="${1:-}"
BOOTLOADER="${2:-}"
CONFIRM="${3:-}"

SD_UBOOT_SECTOR=34
SD_UBOOT_ENV_SECTOR=546
SD_UBOOT_ENV_BLOCKS=64
SD_UBOOT_ENV_CLEAR_SECTOR=514
SD_UBOOT_ENV_CLEAR_BLOCKS=96
INGE_SPL_SIZE=26624
UPSTREAM_UBOOT_SHA256="4d4d4ff27acce1e5e59577c35ef98a505ae42a0bbb07583380463a81cdbfd6a5"
UPSTREAM_UBOOT_SIZE=189685

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
SOURCE_SHA="$(sha256sum "$BOOTLOADER" | awk '{print $1}')"
[ "$SIZE" -eq "$UPSTREAM_UBOOT_SIZE" ] || die "wrong upstream U-Boot size: $SIZE != $UPSTREAM_UBOOT_SIZE"
[ "$SOURCE_SHA" = "$UPSTREAM_UBOOT_SHA256" ] || die "wrong upstream U-Boot SHA256: $SOURCE_SHA"
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
echo "Writing T23N MSC0 1-bit SPL/U-Boot at sector $SD_UBOOT_SECTOR ..."
if ! dd if="$PAD" of="$DEV" bs=512 seek="$SD_UBOOT_SECTOR" count="$BLOCKS" oflag=direct conv=notrunc,fsync status=none 2>/dev/null; then
    dd if="$PAD" of="$DEV" bs=512 seek="$SD_UBOOT_SECTOR" count="$BLOCKS" conv=notrunc,fsync status=none
fi
echo "Writing Ingenic BootROM INGE header at block 0 ..."
python3 - "$DEV" "$INGE_SPL_SIZE" <<'PY'
import os
import struct
import sys

dev = sys.argv[1]
spl_size = int(sys.argv[2])
header = b"INGE" + struct.pack("<I", spl_size) + (b"\x00" * 24) + (b"\xff" * 4)
assert len(header) == 36
with open(dev, "r+b", buffering=0) as f:
    f.seek(0)
    f.write(header)
    f.flush()
    os.fsync(f.fileno())
PY

echo "Clearing legacy + upstream U-Boot environment area (sectors 514..609) ..."
dd if=/dev/zero of="$DEV" bs=512 seek="$SD_UBOOT_ENV_CLEAR_SECTOR" count="$SD_UBOOT_ENV_CLEAR_BLOCKS" conv=notrunc,fsync status=none

sync
blockdev --flushbufs "$DEV" 2>/dev/null || true
sleep 2

if ! dd if="$DEV" of="$READBACK" bs=512 skip="$SD_UBOOT_SECTOR" count="$BLOCKS" iflag=direct status=none 2>/dev/null; then
    dd if="$DEV" of="$READBACK" bs=512 skip="$SD_UBOOT_SECTOR" count="$BLOCKS" status=none
fi
SD_SHA="$(head -c "$SIZE" "$READBACK" | sha256sum | awk '{print $1}')"
DISK_MAGIC="$(od -An -tx4 -N4 "$READBACK" | tr -d ' \n')"

INGE_CHECK="$(python3 - "$DEV" "$INGE_SPL_SIZE" <<'PY'
import struct
import sys

dev = sys.argv[1]
expected_size = int(sys.argv[2])
with open(dev, "rb", buffering=0) as f:
    header = f.read(36)
ok = (
    len(header) == 36
    and header[:4] == b"INGE"
    and struct.unpack("<I", header[4:8])[0] == expected_size
    and header[8:32] == b"\x00" * 24
    and header[32:36] == b"\xff" * 4
)
print("OK" if ok else "BAD")
PY
)"

echo "Bootloader source SHA256 : $SOURCE_SHA"
echo "Bootloader SD SHA256     : $SD_SHA"
echo "SPL magic                : $DISK_MAGIC"
echo "BootROM INGE header      : $INGE_CHECK"

[ "$INGE_CHECK" = "OK" ] || die "BootROM INGE header mismatch at block 0"
[ "$SOURCE_SHA" = "$SD_SHA" ] || die "raw SPL/U-Boot SHA mismatch"
[ "$DISK_MAGIC" = "4d53504c" ] || die "raw SPL magic mismatch"

case "$DEV" in
  /dev/mmcblk*) P1="${DEV}p1"; P2="${DEV}p2" ;;
  *) P1="${DEV}1"; P2="${DEV}2" ;;
esac
[ -b "$P1" ] || die "BOOT partition missing: $P1"
[ -b "$P2" ] || die "ROOTFS partition missing: $P2"

mount "$P1" "$MNT"
cp "$BOOTLOADER" "$MNT/u-boot-t23n-sd.bin"
sync
umount "$MNT"

mount "$P2" "$MNT"
[ -d "$MNT/etc" ] || die "ROOTFS /etc missing"
cat > "$MNT/etc/fw_env.config" <<'EOF'
# T23N upstream MSC0 1-bit U-Boot environment on SD.
# 230 KiB monitor + sector 86 * 512 = 0x44400 = sector 546.
# Device            Device offset   Env size
/dev/mmcblk0         0x44400         0x8000
EOF
sync
umount "$MNT"

echo "BootROM INGE block 0     : OK"
echo "Raw SPL/U-Boot readback  : OK"
echo "Legacy env sector 514    : cleared"
echo "U-Boot env sector 546    : cleared for upstream defaults"
echo "BOOT partition copy      : updated"
echo "ROOTFS fw_env.config     : updated to 0x44400"
