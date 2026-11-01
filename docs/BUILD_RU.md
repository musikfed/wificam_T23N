# Сборка T23/T23N для автономной SD

## Kernel

Для прямого `root=/dev/mmcblk0p2` MMC host driver и EXT4 должны быть
**встроены** в kernel, а не загружаться модулями после mount rootfs.

```sh
sh scripts/build_kernel.sh
```

Скрипт проверяет:

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

Результат:

```text
~/myipcam/build/kernel/arch/mips/boot/uImage
```

Активный kernel загружается upstream U-Boot с FAT32-раздела BOOT как
`/uImage`. В raw sector `0x1800` сохраняется резервная копия; основной boot
path её не читает.

## SD SPL/U-Boot

SPI/SFC U-Boot для этой схемы не используется.

```sh
sh scripts/build_sd_bootloader.sh
```

Скрипт получает точный release asset:

```text
gtxaspec/ingenic-u-boot-xburst1
release: uboot-xb1-2025-09-11
file:    u-boot-isvp_t23n_msc0_mmc1bit.bin
size:    189685 bytes
sha256:  4d4d4ff27acce1e5e59577c35ef98a505ae42a0bbb07583380463a81cdbfd6a5
```

И проверяет размер, SHA-256 и MSPL magic.

MMC image layout начинается с BootROM descriptor:

```text
block 0         INGE + uint32_le(26624) + 24*00 + 4*ff
sector 34       SPL / combined image
sector 86       U-Boot proper
sector 546      U-Boot environment (0x44400), 32 KiB
BOOT:/uImage    активный kernel
/dev/mmcblk0p2  ext4 rootfs
```

Kernel загружается так:

```text
mmc rescan
fatload mmc 0:1 ${baseaddr} uImage
bootm ${baseaddr}
```

## Полная сборка

```sh
sh scripts/build_all.sh
```

После этого полная запись карты:

```sh
sudo sh scripts/flash_full_firmware_sd.sh /dev/sdX
```
