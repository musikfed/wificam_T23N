# Плата T23/T23N и загрузка только с SD

## Аппаратное состояние

Целевая камера использует **Ingenic T23/T23N**, а внешняя SPI/NOR flash
**физически выпаяна**. Проект не должен зависеть от bootloader, environment,
kernel или rootfs во внешней flash.

SD является единственным постоянным загрузочным носителем.

## Цепочка загрузки

```text
T23 BootROM
  ↓
SD sector 34 — MMC SPL (MSC0 1-bit)
  ↓
SD sector 86 — upstream T23N U-Boot
  ↓
p1 BOOT FAT32 — /uImage
  ↓
/dev/mmcblk0p2 — ext4 ROOTFS
```

Используется upstream
`u-boot-isvp_t23n_msc0_mmc1bit.bin`. Его normal kernel path:

```text
mmc rescan
fatload mmc 0:1 ${baseaddr} uImage
bootm ${baseaddr}
```

Root:

```text
root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait init=/init
```

## Первый 1 MiB

```text
0             DOS/MBR partition table
17 KiB        SPL/U-Boot combined image (sector 34)
43 KiB        U-Boot proper (sector 86)
273 KiB       U-Boot env (sector 546 / 0x44400)
3 MiB         резервная raw-копия uImage
1 MiB         p1 BOOT begins (sector 2048); /uImage здесь является активным kernel
```

## Kernel requirements

Для root-on-SD должны быть встроены:

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

## Разделы

| Раздел | Размер | FS | Назначение |
|---|---:|---|---|
| raw boot area | 1 MiB | — | MBR + SPL/U-Boot/env |
| p1 BOOT | 128 MiB | FAT32 | активный /uImage, копия U-Boot, branding |
| p2 ROOTFS | всё свободное до MEDIA | ext4 | Linux/userspace/settings |
| p3 MEDIA | 20 GiB | ext4 | recordings/snapshots/events |

## Первый power-on

После полной offline-проверки SD камера полностью обесточивается, карта
вставляется и затем подаётся питание. UART не является обязательной частью
этого workflow.

Если BootROM не начинает читать SD, проверяются питание SD slot,
card-detect/strap и разводка конкретной платы. При физически отсутствующей
SPI/NOR это уже ранний аппаратный вопрос, а не повод возвращаться к SPI boot.
