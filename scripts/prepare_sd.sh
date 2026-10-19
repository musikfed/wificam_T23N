#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MEDIA_GIB="${MEDIA_GIB:-20}"

# T23 BootROM/U-Boot raw SD layout.
RAW_RESERVE_MIB=16
SD_UBOOT_SECTOR=34
SD_UBOOT_ENV_SECTOR=546
INGE_SPL_SIZE=26624
KERNEL_SECTOR=$((0x1800))
KERNEL_SLOT_SECTORS=$((0x3000))

BOOT_MIB=128
MEDIA_MIB=$((MEDIA_GIB * 1024))
END_RESERVE_MIB=8
MIN_ROOTFS_MIB=2048

usage() {
    echo "Usage: sudo $0 /dev/sdX --yes T23N-SD-u-boot.bin uImage [FULL-rootfs.tar.gz]" >&2
    echo "DESTROYS ALL DATA on the selected SD card." >&2
    echo "This layout is for a T23/T23N camera with NO SPI/NOR boot flash." >&2
    exit 2
}

[ "$#" -ge 4 ] || usage
DEV="$1"
CONFIRM="$2"
BOOTLOADER="$3"
IMAGE="$4"
ROOTFS_TAR="${5:-}"

[ "$CONFIRM" = "--yes" ] || usage
[ "$(id -u)" -eq 0 ] || { echo "Run as root/sudo" >&2; exit 1; }
[ -b "$DEV" ] || { echo "Not a block device: $DEV" >&2; exit 1; }
[ -f "$BOOTLOADER" ] || { echo "SD U-Boot not found: $BOOTLOADER" >&2; exit 1; }
[ -f "$IMAGE" ] || { echo "uImage not found: $IMAGE" >&2; exit 1; }
command -v readlink >/dev/null 2>&1 || { echo "Missing host tool: readlink" >&2; exit 1; }
IMAGE_REAL="$(readlink -f "$IMAGE")"
[ -f "$IMAGE_REAL" ] || { echo "Resolved uImage not found: $IMAGE_REAL" >&2; exit 1; }

case "$DEV" in
  /dev/sd[a-z]|/dev/mmcblk[0-9]) ;;
  *) echo "Refusing suspicious device name: $DEV" >&2; exit 1 ;;
esac

ROOT_SRC="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
case "$ROOT_SRC" in
  "$DEV"*) echo "REFUSING: $DEV contains the running root filesystem" >&2; exit 1 ;;
esac

for cmd in blockdev sfdisk wipefs mkfs.vfat mkfs.ext4 dd od sha256sum stat mount umount lsblk python3; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Missing host tool: $cmd" >&2; exit 1; }
done

part() {
    case "$DEV" in
      /dev/mmcblk*) echo "${DEV}p$1" ;;
      *) echo "${DEV}$1" ;;
    esac
}

BYTES="$(blockdev --getsize64 "$DEV")"
SECTOR_SIZE="$(blockdev --getss "$DEV")"
TOTAL_SECTORS=$((BYTES / SECTOR_SIZE))

[ "$SECTOR_SIZE" -eq 512 ] || {
    echo "REFUSING: T23 raw SD boot layout is defined for 512-byte sectors; got $SECTOR_SIZE" >&2
    exit 1
}

SECTORS_PER_MIB=2048
RAW_RESERVE_SECTORS=$((RAW_RESERVE_MIB * SECTORS_PER_MIB))
BOOT_START=$RAW_RESERVE_SECTORS
BOOT_SECTORS=$((BOOT_MIB * SECTORS_PER_MIB))
MEDIA_SECTORS=$((MEDIA_MIB * SECTORS_PER_MIB))
END_RESERVE_SECTORS=$((END_RESERVE_MIB * SECTORS_PER_MIB))

ROOTFS_START=$((BOOT_START + BOOT_SECTORS))
ROOTFS_SECTORS=$((TOTAL_SECTORS - ROOTFS_START - MEDIA_SECTORS - END_RESERVE_SECTORS))
ROOTFS_SECTORS=$((ROOTFS_SECTORS / SECTORS_PER_MIB * SECTORS_PER_MIB))
MEDIA_START=$((ROOTFS_START + ROOTFS_SECTORS))

ROOTFS_MIB=$((ROOTFS_SECTORS / SECTORS_PER_MIB))
TOTAL_MIB=$((BYTES / 1024 / 1024))

[ "$ROOTFS_MIB" -ge "$MIN_ROOTFS_MIB" ] || {
    echo "REFUSING: card is too small." >&2
    echo "Total: ${TOTAL_MIB} MiB; ROOTFS would be only ${ROOTFS_MIB} MiB." >&2
    exit 1
}

# Validate the specially built MMC SPL/U-Boot image.
UBOOT_MAGIC="$(od -An -tx4 -N4 "$BOOTLOADER" | tr -d ' \n')"
[ "$UBOOT_MAGIC" = "4d53504c" ] || {
    echo "REFUSING: $BOOTLOADER is not a T23 MMC SPL image (magic=$UBOOT_MAGIC)" >&2
    exit 1
}
UBOOT_SIZE="$(stat -c '%s' "$BOOTLOADER")"
UBOOT_MAX=$(((SD_UBOOT_ENV_SECTOR - SD_UBOOT_SECTOR) * 512))
[ "$UBOOT_SIZE" -le "$UBOOT_MAX" ] || {
    echo "REFUSING: bootloader overlaps the SD U-Boot environment area." >&2
    exit 1
}

# uImage is normally a symlink to uImage.lzma. Resolve it once and size
# the opened target file, avoiding symlink-size ambiguity.
KERNEL_SIZE="$(wc -c < "$IMAGE_REAL" | tr -d ' ')"
KERNEL_SLOT_BYTES=$((KERNEL_SLOT_SECTORS * 512))
[ "$KERNEL_SIZE" -le "$KERNEL_SLOT_BYTES" ] || {
    echo "REFUSING: uImage is $KERNEL_SIZE bytes, raw kernel slot is $KERNEL_SLOT_BYTES bytes." >&2
    exit 1
}

# Generate PegineLab jingle if needed.
if [ ! -f "$REPO_DIR/web/assets/boot-jingle.wav" ] && command -v python3 >/dev/null 2>&1; then
    python3 "$REPO_DIR/tools/generate_boot_jingle.py"
fi

echo "WARNING: ALL DATA ON $DEV WILL BE DESTROYED"
echo
echo "AUTONOMOUS T23N SD layout (no SPI/NOR):"
echo "  raw 0..16 MiB : BootROM/SPL/U-Boot/env + redundant raw uImage backup"
echo "  SPL/U-Boot    : sector $SD_UBOOT_SECTOR (17 KiB)"
echo "  kernel boot   : BOOT FAT32 /uImage"
echo "  kernel backup : sector 0x1800 (3 MiB), slot 6 MiB"
echo "  BOOT          : ${BOOT_MIB} MiB FAT32, starts at ${RAW_RESERVE_MIB} MiB"
echo "  ROOTFS        : ${ROOTFS_MIB} MiB ext4 (/dev/mmcblk0p2)"
echo "  MEDIA         : ${MEDIA_MIB} MiB ext4 (${MEDIA_GIB} GiB)"
echo
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS "$DEV"
sleep 2

for n in 1 2 3; do
    umount "$(part "$n")" 2>/dev/null || true
done

# Clear the complete raw boot area first. Partition filesystems start at 16 MiB.
dd if=/dev/zero of="$DEV" bs=1M count="$RAW_RESERVE_MIB" conv=fsync status=none
wipefs -a "$DEV" >/dev/null 2>&1 || true

sfdisk "$DEV" <<EOF
label: dos
unit: sectors

start=$BOOT_START, size=$BOOT_SECTORS, type=0c, bootable
start=$ROOTFS_START, size=$ROOTFS_SECTORS, type=83
start=$MEDIA_START, size=$MEDIA_SECTORS, type=83
EOF

# Ingenic MMC BootROM descriptor. Keep bytes 446..509 (DOS partition table)
# and 510..511 (0x55aa signature) untouched.
python3 - "$DEV" "$INGE_SPL_SIZE" <<'PY'
import os
import struct
import sys

dev = sys.argv[1]
spl_size = int(sys.argv[2])
header = b"INGE" + struct.pack("<I", spl_size) + (b"\x00" * 24) + (b"\xff" * 4)
with open(dev, "r+b", buffering=0) as f:
    f.seek(0)
    f.write(header)
    f.flush()
    os.fsync(f.fileno())
PY

sync
partprobe "$DEV" 2>/dev/null || true
sleep 2

P1="$(part 1)"
P2="$(part 2)"
P3="$(part 3)"
[ -b "$P1" ] && [ -b "$P2" ] && [ -b "$P3" ] || {
    echo "Partition nodes did not appear: $P1 $P2 $P3" >&2
    exit 1
}

mkfs.vfat -F 32 -n BOOT "$P1"

# Linux 3.10 must mount ROOTFS before any userspace is available. Do not use
# Ubuntu 24.04's newer default ext4 incompat features (notably orphan_file and
# metadata checksums/64-bit layout) on either filesystem the camera mounts.
EXT4_COMPAT_OPTS="-O ^64bit,^metadata_csum,^orphan_file"
mkfs.ext4 -F $EXT4_COMPAT_OPTS -L ROOTFS "$P2"
mkfs.ext4 -F $EXT4_COMPAT_OPTS -L MEDIA "$P3"

echo "Writing T23N SD SPL/U-Boot at sector $SD_UBOOT_SECTOR ..."
dd if="$BOOTLOADER" of="$DEV" bs=512 seek="$SD_UBOOT_SECTOR" conv=notrunc,fsync status=none

INGE_CHECK="$(python3 - "$DEV" "$INGE_SPL_SIZE" <<'PY'
import struct
import sys
dev = sys.argv[1]
expected_size = int(sys.argv[2])
with open(dev, "rb", buffering=0) as f:
    h = f.read(36)
print("OK" if (
    len(h) == 36 and h[:4] == b"INGE"
    and struct.unpack("<I", h[4:8])[0] == expected_size
    and h[8:32] == b"\x00" * 24
    and h[32:36] == b"\xff" * 4
) else "BAD")
PY
)"
[ "$INGE_CHECK" = "OK" ] || {
    echo "REFUSING: INGE BootROM header verification failed" >&2
    exit 1
}

DISK_MAGIC="$(dd if="$DEV" bs=512 skip="$SD_UBOOT_SECTOR" count=1 status=none | od -An -tx4 -N4 | tr -d ' \n')"
[ "$DISK_MAGIC" = "4d53504c" ] || {
    echo "REFUSING: SPL readback magic mismatch: $DISK_MAGIC" >&2
    exit 1
}

echo "Writing and verifying redundant raw uImage backup at sector 0x1800 ..."
EXPECTED_KERNEL_SHA="$(sha256sum "$IMAGE_REAL" | awk '{print $1}')"
sh "$REPO_DIR/scripts/write_verify_raw_kernel.sh" "$DEV" "$IMAGE_REAL" --yes

VERIFY="$(mktemp)"
MNT="$(mktemp -d)"
cleanup() {
    umount "$MNT" 2>/dev/null || true
    rm -f "$VERIFY"
    rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mount "$P1" "$MNT"
cp "$IMAGE_REAL" "$MNT/uImage"
cp "$BOOTLOADER" "$MNT/u-boot-t23n-sd.bin"
if [ -f "$REPO_DIR/branding/peginelab-logo.png.b64" ]; then
    base64 -d "$REPO_DIR/branding/peginelab-logo.png.b64" > "$MNT/peginelab-logo.png"
fi
[ -f "$REPO_DIR/web/assets/boot-jingle.wav" ] && cp "$REPO_DIR/web/assets/boot-jingle.wav" "$MNT/boot-jingle.wav"
cat > "$MNT/SD-BOOT-MAP.txt" <<EOF
T23N autonomous SD boot map
SPI/NOR required: NO
SPL/U-Boot raw start: sector 34 (17 KiB)
U-Boot proper raw start: sector 86
U-Boot environment raw start: sector 546 (0x44400)
Kernel boot source: BOOT FAT32 /uImage
Redundant kernel raw backup: sector 0x1800 (3 MiB)
Kernel raw slot: 0x3000 sectors (6 MiB)
Root filesystem: /dev/mmcblk0p2, ext4
BOOT partition: p1, FAT32, starts at 16 MiB
MEDIA partition: p3, ext4
uImage SHA256: $EXPECTED_KERNEL_SHA
EOF
sync
umount "$MNT"

if [ -n "$ROOTFS_TAR" ]; then
    [ -f "$ROOTFS_TAR" ] || { echo "rootfs archive not found: $ROOTFS_TAR" >&2; exit 1; }
    mount "$P2" "$MNT"
    tar -C "$MNT" -xzf "$ROOTFS_TAR"
    [ -x "$MNT/bin/sh" ] || { echo "REFUSING: rootfs missing /bin/sh" >&2; exit 1; }
    [ -x "$MNT/init" ] || { echo "REFUSING: rootfs missing /init" >&2; exit 1; }
    mkdir -p "$MNT/data" "$MNT/mnt/media"
    sync
    umount "$MNT"
fi

mount "$P3" "$MNT"
mkdir -p "$MNT/recordings" "$MNT/snapshots" "$MNT/events"
sync
umount "$MNT"

sync

echo
echo "AUTONOMOUS SD CARD PREPARED:"
lsblk -f "$DEV"
echo
echo "BootROM INGE header: OK (block 0)"
echo "SPL/U-Boot raw boot: OK (sector 34)"
echo "BOOT/uImage is the active kernel boot source"
echo "Redundant raw kernel readback: OK ($EXPECTED_KERNEL_SHA)"
echo "ROOTFS: $P2"
echo "MEDIA: recordings/ snapshots/ events/"
echo
echo "This card is intended to boot the T23N with the SPI/NOR flash physically absent."
