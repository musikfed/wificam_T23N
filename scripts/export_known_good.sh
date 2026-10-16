#!/bin/sh
set -eu

PROJECT_ROOT="${PROJECT_ROOT:-$HOME/myipcam}"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build/kernel}"
OUT="${1:-$PROJECT_ROOT/deploy/t23n-known-good}"

mkdir -p "$OUT"

copy_if() {
    [ -e "$1" ] && cp -L "$1" "$OUT/$2"
}

copy_if "$BUILD_DIR/arch/mips/boot/uImage" uImage
copy_if "$BUILD_DIR/arch/mips/boot/uImage.lzma" uImage.lzma
copy_if "$BUILD_DIR/vmlinux" vmlinux
copy_if "$BUILD_DIR/System.map" System.map
copy_if "$BUILD_DIR/.config" kernel.config

(
  cd "$OUT"
  sha256sum * > SHA256SUMS
)

echo "Known-good snapshot: $OUT"
cat "$OUT/SHA256SUMS"
