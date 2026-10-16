#!/bin/sh
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

echo "[1/2] Building kernel"
sh "$HERE/scripts/build_kernel.sh"

echo "[2/2] Packaging WIFICAM rootfs overlay"
sh "$HERE/scripts/package_rootfs_overlay.sh"

if [ -n "${BASE_ROOTFS:-}" ]; then
    echo "[optional] Assembling complete rootfs from: $BASE_ROOTFS"
    sh "$HERE/scripts/assemble_rootfs.sh" "$BASE_ROOTFS"
fi

echo
echo "Artifacts:"
echo "  kernel : $HOME/myipcam/build/kernel/arch/mips/boot/uImage"
echo "  overlay: $HERE/out/wificam-rootfs-overlay.tar.gz"
if [ -n "${BASE_ROOTFS:-}" ]; then
    echo "  rootfs : $HERE/out/wificam-rootfs.tar.gz"
else
    echo "  rootfs : not assembled (set BASE_ROOTFS=/path/base-rootfs.tar.gz)"
fi
