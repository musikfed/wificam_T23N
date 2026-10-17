#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$HOME/myipcam}"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build/kernel}"
OUT="${1:-$PROJECT_ROOT/deploy/t23n-autonomous-sd}"

KERNEL="$BUILD_DIR/arch/mips/boot/uImage"
UBOOT="$REPO_DIR/out/u-boot-t23n-sd.bin"

[ -f "$KERNEL" ] || { echo "Missing kernel: $KERNEL" >&2; exit 1; }
[ -f "$BUILD_DIR/.config" ] || { echo "Missing kernel config" >&2; exit 1; }
[ -f "$UBOOT" ] || { echo "Missing SD U-Boot: $UBOOT" >&2; exit 1; }

for opt in CONFIG_MMC CONFIG_MMC_BLOCK CONFIG_JZMMC_V12 CONFIG_JZMMC_V12_MMC0 CONFIG_EXT4_FS; do
    grep -q "^$opt=y$" "$BUILD_DIR/.config" || {
        echo "Refusing export: $opt is not built-in" >&2
        exit 1
    }
done

mkdir -p "$OUT"
cp -L "$KERNEL" "$OUT/uImage"
cp "$BUILD_DIR/.config" "$OUT/kernel.config"
cp "$UBOOT" "$OUT/u-boot-t23n-sd.bin"

[ -f "$REPO_DIR/out/wificam-rootfs-overlay.tar.gz" ] &&     cp "$REPO_DIR/out/wificam-rootfs-overlay.tar.gz" "$OUT/"

cat > "$OUT/BOOT-MAP.txt" <<'EOF'
T23N autonomous SD
SPI/NOR required: NO
SPL/U-Boot: raw sector 34
U-Boot proper: sector 86
Environment: sector 514
Kernel: raw sector 0x1800, 0x3000-sector slot
Rootfs: /dev/mmcblk0p2 ext4
EOF

(
  cd "$OUT"
  sha256sum uImage u-boot-t23n-sd.bin kernel.config > SHA256SUMS
  [ ! -f wificam-rootfs-overlay.tar.gz ] || sha256sum wificam-rootfs-overlay.tar.gz >> SHA256SUMS
)

echo "Autonomous-SD snapshot: $OUT"
cat "$OUT/SHA256SUMS"
