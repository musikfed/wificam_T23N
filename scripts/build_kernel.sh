#!/bin/sh
set -eu

PROJECT_ROOT="${PROJECT_ROOT:-$HOME/myipcam}"
KERNEL_SRC="${KERNEL_SRC:-$PROJECT_ROOT/kernel/openipc-linux}"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build/kernel}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
TARGET="${TARGET:-uImage.lzma}"

TOOLCHAIN_BIN="${TOOLCHAIN_BIN:-$PROJECT_ROOT/toolchain/openipc-ingenic/mipsel-openipc-linux-musl_sdk-buildroot/bin}"
CROSS_COMPILE="${CROSS_COMPILE:-$TOOLCHAIN_BIN/mipsel-openipc-linux-musl-}"

die() { echo "ERROR: $*" >&2; exit 1; }

[ -d "$KERNEL_SRC" ] || die "kernel source not found: $KERNEL_SRC"
[ -x "${CROSS_COMPILE}gcc" ] || die "cross compiler not found: ${CROSS_COMPILE}gcc"
[ -f "$KERNEL_SRC/scripts/config" ] || die "kernel scripts/config not found"

mkdir -p "$BUILD_DIR"

echo "=============================================="
echo " WIFICAM T23/T23N autonomous-SD kernel build"
echo "=============================================="
echo "source : $KERNEL_SRC"
echo "output : $BUILD_DIR"
echo "cross  : $CROSS_COMPILE"
echo "jobs   : $JOBS"
echo "target : $TARGET"
echo

if [ ! -f "$BUILD_DIR/.config" ]; then
    if [ -f "$KERNEL_SRC/.config" ]; then
        cp "$KERNEL_SRC/.config" "$BUILD_DIR/.config"
    else
        die "no .config found. Put the known-good T23 config in $BUILD_DIR/.config"
    fi
fi

# With the SPI/NOR physically absent, the kernel must be able to mount the SD
# root filesystem without loading a module from that same filesystem first.
CFG="$KERNEL_SRC/scripts/config"
bash "$CFG" --file "$BUILD_DIR/.config" \
    --enable MMC \
    --enable MMC_BLOCK \
    --enable JZMMC_V12 \
    --enable JZMMC_V12_SDMA \
    --enable JZMMC_V12_MMC0 \
    --enable JZMMC_V12_MMC0_PB_4BIT \
    --enable EXT4_FS \
    --enable PARTITION_ADVANCED \
    --enable MSDOS_PARTITION \
    --enable DEVTMPFS \
    --enable DEVTMPFS_MOUNT \
    --enable TMPFS

make -C "$KERNEL_SRC" O="$BUILD_DIR" ARCH=mips CROSS_COMPILE="$CROSS_COMPILE" olddefconfig

require_y() {
    grep -q "^$1=y$" "$BUILD_DIR/.config" || die "$1 must be built-in (=y) for autonomous SD root"
}

require_y CONFIG_MMC
require_y CONFIG_MMC_BLOCK
require_y CONFIG_JZMMC_V12
require_y CONFIG_JZMMC_V12_MMC0
require_y CONFIG_EXT4_FS
require_y CONFIG_MSDOS_PARTITION
require_y CONFIG_DEVTMPFS
require_y CONFIG_DEVTMPFS_MOUNT

make -C "$KERNEL_SRC" O="$BUILD_DIR" ARCH=mips CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS" "$TARGET"

IMAGE="$BUILD_DIR/arch/mips/boot/uImage"
[ -e "$IMAGE" ] || IMAGE="$BUILD_DIR/arch/mips/boot/uImage.lzma"
[ -e "$IMAGE" ] || die "uImage was not produced"

size="$(wc -c < "$IMAGE" | tr -d ' ')"
max=$((6 * 1024 * 1024))
[ "$size" -le "$max" ] || die "uImage is too large for the 6 MiB raw SD kernel slot: $size bytes"

echo
if command -v mkimage >/dev/null 2>&1; then
    mkimage -l "$IMAGE"
else
    echo "NOTE: mkimage not installed; header check skipped"
fi

echo
echo "Required SD-root config:"
grep -E '^(CONFIG_MMC|CONFIG_MMC_BLOCK|CONFIG_JZMMC_V12|CONFIG_JZMMC_V12_MMC0|CONFIG_EXT4_FS|CONFIG_MSDOS_PARTITION|CONFIG_DEVTMPFS|CONFIG_DEVTMPFS_MOUNT)=' "$BUILD_DIR/.config"

echo
sha256sum "$IMAGE"

echo
echo "=============================================="
echo " Autonomous-SD kernel build: SUCCESS"
echo "=============================================="
echo "$IMAGE"
