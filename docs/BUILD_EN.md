# T23/T23N autonomous-SD build

## Kernel

For direct `root=/dev/mmcblk0p2`, the MMC host driver and EXT4 must be built
**into** the kernel, not loaded as modules after the root filesystem mount.

```sh
sh scripts/build_kernel.sh
```

The script verifies:

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

The active kernel is loaded by upstream U-Boot from the FAT32 BOOT partition as
`/uImage`. A redundant copy is also stored at raw sector `0x1800`; the
normal boot path does not read that backup.

## SD SPL/U-Boot

A SPI/SFC U-Boot image is not used for this layout.

```sh
sh scripts/build_sd_bootloader.sh
```

The script downloads and verifies this exact release asset:

```text
gtxaspec/ingenic-u-boot-xburst1
release: uboot-xb1-2025-09-11
file:    u-boot-isvp_t23n_msc0_mmc1bit.bin
size:    189685 bytes
sha256:  4d4d4ff27acce1e5e59577c35ef98a505ae42a0bbb07583380463a81cdbfd6a5
```

The MMC image starts with the Ingenic BootROM descriptor:

```text
block 0         INGE + uint32_le(26624) + 24*00 + 4*ff
sector 34       SPL / combined image
sector 86       U-Boot proper
sector 546      U-Boot environment (0x44400), 32 KiB
BOOT:/uImage    active kernel
/dev/mmcblk0p2  ext4 rootfs
```

Kernel load path:

```text
mmc rescan
fatload mmc 0:1 ${baseaddr} uImage
bootm ${baseaddr}
```

## Build everything

```sh
sh scripts/build_all.sh
```

Then write the complete card with:

```sh
sudo sh scripts/flash_full_firmware_sd.sh /dev/sdX
```
