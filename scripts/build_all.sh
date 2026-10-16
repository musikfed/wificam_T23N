#!/bin/sh
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

echo "[1/2] Building kernel"
sh "$HERE/scripts/build_kernel.sh"

echo "[2/2] Packaging web/rootfs overlay"
sh "$HERE/scripts/package_rootfs_overlay.sh"

echo
echo "Artifacts:"
echo "  kernel: $HOME/myipcam/build/kernel/arch/mips/boot/uImage"
echo "  overlay: $HERE/out/wificam-rootfs-overlay.tar.gz"
