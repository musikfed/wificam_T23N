# Сборка T23/T23N для автономной SD

## Что изменилось

Старый kernel, собранный до перехода на SD-only, загружался как MIPS uImage, но
не является финальным deployable kernel: для прямого `root=/dev/mmcblk0p2`
нужны MMC host driver и EXT4 **встроенными** в kernel.

## Kernel

```sh
sh scripts/build_kernel.sh
```

Скрипт принудительно включает и после `olddefconfig` проверяет:

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

Kernel ограничен raw slot размером 6 MiB, потому что SD U-Boot выполняет:

```text
mmc read 0x80600000 0x1800 0x3000
```

После новой сборки использовать SHA-256, который печатает сам build script.
Старый pre-SD-root hash не следует использовать как критерий готовности.

## SD SPL/U-Boot

Обычный SPI/SFC U-Boot здесь не подходит.

```sh
sh scripts/build_sd_bootloader.sh
```

Скрипт использует pinned OpenIPC `u-boot-ingenic`, добавляет T23N MMC target:

```text
SPL_MMC_SUPPORT
ENV_IS_IN_MMC
JZ_MMC_MSC0
T23N
```

и bootargs:

```text
root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait init=/init
```

Результат:

```text
out/u-boot-t23n-sd.bin
```

Build script проверяет MMC SPL magic и размер image, чтобы U-Boot не пересёк
свою environment area.

## Полная сборка

```sh
sh scripts/build_all.sh
```

Это последовательно собирает:

1. autonomous-SD kernel;
2. T23N MMC SPL/U-Boot;
3. WIFICAM/PegineLab rootfs overlay.

После этого карта записывается:

```sh
sudo sh scripts/flash_full_firmware_sd.sh /dev/sdX
```
