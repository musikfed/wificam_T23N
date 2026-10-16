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

mkdir -p "$BUILD_DIR"

echo "=============================================="
echo " MyIPCam T23/T23N kernel build"
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
        die "no .config found. Put the known-good config in $BUILD_DIR/.config"
    fi
fi

make -C "$KERNEL_SRC" O="$BUILD_DIR" ARCH=mips CROSS_COMPILE="$CROSS_COMPILE" olddefconfig
make -C "$KERNEL_SRC" O="$BUILD_DIR" ARCH=mips CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS" "$TARGET"

IMAGE="$BUILD_DIR/arch/mips/boot/uImage"
[ -e "$IMAGE" ] || IMAGE="$BUILD_DIR/arch/mips/boot/uImage.lzma"
[ -e "$IMAGE" ] || die "uImage was not produced"

echo
if command -v mkimage >/dev/null 2>&1; then
    mkimage -l "$IMAGE"
else
    echo "NOTE: mkimage not installed; header check skipped"
fi

sha256sum "$IMAGE"

echo
echo "=============================================="
echo " MyIPCam T23/T23N kernel build: SUCCESS"
echo "=============================================="
echo "$IMAGE"
