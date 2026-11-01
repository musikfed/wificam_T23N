#!/bin/sh
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

echo "[1/3] Building autonomous-SD kernel"
sh "$HERE/scripts/build_kernel.sh"

echo "[2/3] Preparing verified upstream T23N SD SPL/U-Boot"
sh "$HERE/scripts/build_sd_bootloader.sh"

echo "[3/3] Packaging WIFICAM/PegineLab rootfs overlay"
sh "$HERE/scripts/package_rootfs_overlay.sh"

echo
echo "Autonomous-SD artifacts:"
echo "  kernel     : $HOME/myipcam/build/kernel/arch/mips/boot/uImage"
echo "  SD U-Boot  : $HERE/out/u-boot-t23n-sd.bin"
echo "  overlay    : $HERE/out/wificam-rootfs-overlay.tar.gz"
echo
echo "Write the complete SD firmware with:"
echo "  sudo sh $HERE/scripts/flash_full_firmware_sd.sh /dev/YOUR_SD"
