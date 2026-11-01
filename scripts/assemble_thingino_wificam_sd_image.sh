#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
UBOOT="${1:-}"
KERNEL="${2:-}"
ROOTFS="${3:-}"
OUT="${4:-$REPO_DIR/Thingino/thingino-t23-sd.bin}"

die() { echo "ERROR: $*" >&2; exit 1; }

[ -f "$UBOOT" ] || die "MMC U-Boot not found: $UBOOT"
[ -f "$KERNEL" ] || die "uImage not found: $KERNEL"
[ -f "$ROOTFS" ] || die "rootfs.ext2 not found: $ROOTFS"

for cmd in dd mkfs.vfat mcopy mdir python3 sha256sum stat od head truncate; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd not installed"
done

SECTOR=512
UBOOT_START=34
UBOOT_ENV_START=546
BOOT_START=2048
BOOT_MIB=16
BOOT_SECTORS=$((BOOT_MIB * 1024 * 1024 / SECTOR))
ROOT_START=$((BOOT_START + BOOT_SECTORS))

UBOOT_SIZE="$(stat -c '%s' "$UBOOT")"
KERNEL_SIZE="$(stat -c '%s' "$KERNEL")"
ROOT_SIZE="$(stat -c '%s' "$ROOTFS")"

[ $((ROOT_SIZE % SECTOR)) -eq 0 ] || die "rootfs.ext2 size is not sector aligned: $ROOT_SIZE"
ROOT_SECTORS=$((ROOT_SIZE / SECTOR))
TOTAL_SECTORS=$((ROOT_START + ROOT_SECTORS))
TOTAL_SIZE=$((TOTAL_SECTORS * SECTOR))

UBOOT_MAX=$(((UBOOT_ENV_START - UBOOT_START) * SECTOR))
[ "$UBOOT_SIZE" -le "$UBOOT_MAX" ] || die "MMC U-Boot overlaps environment area"
MAGIC="$(od -An -tx4 -N4 "$UBOOT" | tr -d ' \n')"
[ "$MAGIC" = "4d53504c" ] || die "MMC U-Boot has wrong MSPL magic: $MAGIC"

[ "$KERNEL_SIZE" -lt $((BOOT_MIB * 1024 * 1024 - 1024 * 1024)) ] || \
    die "uImage is too large for the BOOT partition: $KERNEL_SIZE"

TMPDIR="$(mktemp -d)"
TMP_OUT="$OUT.tmp"
BOOTFS="$TMPDIR/boot.fat"
cleanup() {
    rm -rf "$TMPDIR"
    rm -f "$TMP_OUT"
}
trap cleanup EXIT INT TERM

mkdir -p "$(dirname "$OUT")"
rm -f "$TMP_OUT"

# 16 MiB is intentionally FAT16: forcing FAT32 at this size creates a
# non-standard too-small FAT32 cluster count. U-Boot fatload supports FAT16.
dd if=/dev/zero of="$BOOTFS" bs=1M count="$BOOT_MIB" status=none
mkfs.vfat -F 16 -n BOOT "$BOOTFS" >/dev/null
mcopy -o -i "$BOOTFS" "$KERNEL" ::/uImage
mdir -i "$BOOTFS" ::/uImage >/dev/null

# Sector 0 is a normal DOS/MBR. Ingenic MMC BootROM finds MSPL at LBA34.
truncate -s "$TOTAL_SIZE" "$TMP_OUT"

python3 - "$TMP_OUT" "$BOOT_START" "$BOOT_SECTORS" "$ROOT_START" "$ROOT_SECTORS" <<'PY'
import struct
import sys

path = sys.argv[1]
boot_start, boot_size, root_start, root_size = map(int, sys.argv[2:])
mbr = bytearray(512)

def put_part(offset, bootable, ptype, start, size):
    entry = bytearray(16)
    entry[0] = 0x80 if bootable else 0x00
    entry[1:4] = bytes((0xFE, 0xFF, 0xFF))
    entry[4] = ptype
    entry[5:8] = bytes((0xFE, 0xFF, 0xFF))
    entry[8:12] = struct.pack("<I", start)
    entry[12:16] = struct.pack("<I", size)
    mbr[offset:offset + 16] = entry

put_part(0x1BE, True, 0x0E, boot_start, boot_size)
put_part(0x1CE, False, 0x83, root_start, root_size)
mbr[510:512] = b"\x55\xaa"

with open(path, "r+b") as f:
    f.seek(0)
    f.write(mbr)
PY

dd if="$UBOOT" of="$TMP_OUT" bs="$SECTOR" seek="$UBOOT_START" conv=notrunc status=none
dd if="$BOOTFS" of="$TMP_OUT" bs="$SECTOR" seek="$BOOT_START" conv=notrunc status=none
dd if="$ROOTFS" of="$TMP_OUT" bs="$SECTOR" seek="$ROOT_START" conv=notrunc status=none

python3 - "$TMP_OUT" "$BOOT_START" "$BOOT_SECTORS" "$ROOT_START" "$ROOT_SECTORS" <<'PY'
import struct
import sys

path = sys.argv[1]
expected = tuple(map(int, sys.argv[2:]))
with open(path, "rb") as f:
    mbr = f.read(512)
if mbr[510:512] != b"\x55\xaa":
    raise SystemExit("MBR signature missing")
p1_start, p1_size = struct.unpack("<II", mbr[0x1C6:0x1CE])
p2_start, p2_size = struct.unpack("<II", mbr[0x1D6:0x1DE])
if (p1_start, p1_size, p2_start, p2_size) != expected:
    raise SystemExit(
        f"partition geometry mismatch: {(p1_start,p1_size,p2_start,p2_size)} != {expected}"
    )
if mbr[0x1C2] != 0x0E or mbr[0x1D2] != 0x83:
    raise SystemExit("partition types are wrong")
PY

DISK_MAGIC="$(dd if="$TMP_OUT" bs="$SECTOR" skip="$UBOOT_START" count=1 status=none | od -An -tx4 -N4 | tr -d ' \n')"
[ "$DISK_MAGIC" = "4d53504c" ] || die "MSPL magic missing at LBA34 after assembly"

UBOOT_BLOCKS=$(((UBOOT_SIZE + SECTOR - 1) / SECTOR))
READ_UBOOT_SHA="$(
    dd if="$TMP_OUT" bs="$SECTOR" skip="$UBOOT_START" count="$UBOOT_BLOCKS" status=none |
    head -c "$UBOOT_SIZE" | sha256sum | awk '{print $1}'
)"
[ "$READ_UBOOT_SHA" = "$(sha256sum "$UBOOT" | awk '{print $1}')" ] || \
    die "MMC U-Boot readback SHA mismatch"

BOOT_READ_SHA="$(
    dd if="$TMP_OUT" bs="$SECTOR" skip="$BOOT_START" count="$BOOT_SECTORS" status=none |
    sha256sum | awk '{print $1}'
)"
[ "$BOOT_READ_SHA" = "$(sha256sum "$BOOTFS" | awk '{print $1}')" ] || \
    die "BOOT filesystem readback SHA mismatch"

ROOT_READ_SHA="$(
    dd if="$TMP_OUT" bs="$SECTOR" skip="$ROOT_START" count="$ROOT_SECTORS" status=none |
    sha256sum | awk '{print $1}'
)"
[ "$ROOT_READ_SHA" = "$(sha256sum "$ROOTFS" | awk '{print $1}')" ] || \
    die "ROOTFS readback SHA mismatch"

mv "$TMP_OUT" "$OUT"
trap - EXIT INT TERM
rm -rf "$TMPDIR"

echo
echo "THINGINO DIRECT SD IMAGE: ASSEMBLED + VERIFIED"
echo "Output        : $OUT"
echo "Size          : $TOTAL_SIZE bytes"
echo "MBR           : DOS/MBR + 55aa"
echo "MMC U-Boot    : LBA $UBOOT_START (MSPL verified)"
echo "BOOT p1       : LBA $BOOT_START, $BOOT_MIB MiB FAT16, /uImage"
echo "ROOTFS p2     : LBA $ROOT_START, $ROOT_SIZE bytes ext4"
echo "Linux root    : /dev/mmcblk0p2"
sha256sum "$OUT"
