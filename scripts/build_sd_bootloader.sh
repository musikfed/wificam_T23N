#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT="${UBOOT_SD_OUT:-$REPO_DIR/out/u-boot-t23n-sd.bin}"

# Use the exact prebuilt T23N MSC0 1-bit MMC image used by the Thingino
# installer toolchain. Do not rebuild an older OpenIPC U-Boot and patch it
# locally: the upstream binary also contains later T23/T23N MMC fixes and the
# MMC boot command that loads /uImage from FAT partition 1.
UBOOT_TAG="uboot-xb1-2025-09-11"
UBOOT_NAME="u-boot-isvp_t23n_msc0_mmc1bit.bin"
UBOOT_URL="https://github.com/gtxaspec/ingenic-u-boot-xburst1/releases/download/$UBOOT_TAG/$UBOOT_NAME"
UBOOT_SHA256="4d4d4ff27acce1e5e59577c35ef98a505ae42a0bbb07583380463a81cdbfd6a5"
UBOOT_SIZE=189685

die() { echo "ERROR: $*" >&2; exit 1; }

for cmd in curl sha256sum od wc; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd not installed"
done

mkdir -p "$(dirname "$OUT")"
TMP="$OUT.tmp"
rm -f "$TMP"

echo "[1/3] Downloading pinned upstream T23N MSC0 1-bit U-Boot..."
curl -fL --retry 3 --connect-timeout 20 -o "$TMP" "$UBOOT_URL"

echo "[2/3] Verifying exact release asset..."
SIZE="$(wc -c < "$TMP" | tr -d ' ')"
[ "$SIZE" -eq "$UBOOT_SIZE" ] || {
    rm -f "$TMP"
    die "unexpected U-Boot size: $SIZE != $UBOOT_SIZE"
}
echo "$UBOOT_SHA256  $TMP" | sha256sum -c - >/dev/null || {
    rm -f "$TMP"
    die "upstream U-Boot SHA256 mismatch"
}
MAGIC="$(od -An -tx4 -N4 "$TMP" | tr -d ' \n')"
[ "$MAGIC" = "4d53504c" ] || {
    rm -f "$TMP"
    die "unexpected SPL magic: $MAGIC (expected 4d53504c)"
}

# Upstream layout for this exact build:
# combined image at sector 34, 26 KiB SPL => U-Boot proper at sector 86.
# CONFIG_SYS_MONITOR_LEN is 230 KiB, therefore MMC env starts at:
#   230 KiB + 86*512 = 0x44400 = sector 546.
MAX=$(((546 - 34) * 512))
[ "$SIZE" -le "$MAX" ] || {
    rm -f "$TMP"
    die "bootloader overlaps upstream MMC environment area"
}

echo "[3/3] Installing verified bootloader artifact..."
mv "$TMP" "$OUT"

echo
echo "T23N UPSTREAM SD BOOTLOADER READY (MSC0 1-bit):"
ls -lh "$OUT"
sha256sum "$OUT"
echo
echo "Upstream release        : gtxaspec/ingenic-u-boot-xburst1 $UBOOT_TAG"
echo "BootROM block 0 header  : INGE, SPL size 26624 bytes"
echo "BootROM raw SPL start   : sector 34 (17 KiB)"
echo "SD bus mode             : MSC0 1-bit"
echo "U-Boot proper start     : sector 86"
echo "U-Boot env start        : sector 546 (0x44400)"
echo "Kernel boot source      : FAT32 partition 1, /uImage"
echo "Linux root              : /dev/mmcblk0p2 (ext4)"
