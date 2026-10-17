# T23/T23N autonomous-SD build

## Kernel

The old pre-SD-only kernel image is not the final deployable reference. Direct
`root=/dev/mmcblk0p2` requires the MMC host driver and EXT4 to be built into
the kernel.

Build:

```sh
sh scripts/build_kernel.sh
```

The script forces and verifies:

```text
CONFIG_MMC=y
CONFIG_MMC_BLOCK=y
CONFIG_JZMMC_V12=y
CONFIG_JZMMC_V12_MMC0=y
CONFIG_EXT4_FS=y
CONFIG_MSDOS_PARTITION=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
```

Result:

```text
~/myipcam/build/kernel/arch/mips/boot/uImage
```

The kernel must fit the 6 MiB raw slot read by U-Boot:

```text
mmc read 0x80600000 0x1800 0x3000
```

Use the SHA-256 printed by the new build. The previous pre-SD-root hash is not a
deployment readiness check.

## SD SPL/U-Boot

A normal SPI/SFC U-Boot image is not suitable.

```sh
sh scripts/build_sd_bootloader.sh
```

The script pins OpenIPC `u-boot-ingenic`, creates a T23N MMC target with
`SPL_MMC_SUPPORT`, `ENV_IS_IN_MMC`, `JZ_MMC_MSC0` and `T23N`, and uses:

```text
root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait init=/init
```

Result:

```text
out/u-boot-t23n-sd.bin
```

The build validates the MMC SPL magic and that the combined image does not
overlap its SD environment area.

## Build everything

```sh
sh scripts/build_all.sh
```

This builds the autonomous-SD kernel, T23N MMC SPL/U-Boot and WIFICAM/PegineLab
overlay.

Write the complete card with:

```sh
sudo sh scripts/flash_full_firmware_sd.sh /dev/sdX
```
