# Плата T23/T23N и загрузка только с SD

## Аппаратное состояние

Целевая камера использует **Ingenic T23/T23N**, а внешняя SPI/NOR flash
**физически выпаяна**. Поэтому проект не должен зависеть от:

- U-Boot во внешней flash;
- environment во внешней flash;
- kernel во внешней flash;
- rootfs во внешней flash.

SD является единственным постоянным загрузочным носителем.

## Цепочка загрузки

```text
T23 BootROM
  ↓
SD sector 34 — MMC SPL
  ↓
SD sector 86 — U-Boot proper
  ↓
SD sector 0x1800 — uImage
  ↓
/dev/mmcblk0p2 — ext4 ROOTFS
```

T23 source tree содержит MMC SPL path и boot command:

```text
mmc read 0x80600000 0x1800 0x3000
bootm 0x80600000
```

Наш T23N MMC U-Boot дополнительно передаёт:

```text
root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait init=/init
```

## Почему первые 16 MiB не являются разделом

Raw boot components должны находиться по фиксированным секторам, поэтому
partition 1 начинается только с 16 MiB.

```text
0            MBR
17 KiB       SPL/U-Boot combined image
43 KiB       U-Boot proper (sector 86)
257 KiB      U-Boot env (sector 514)
3 MiB        raw uImage
3–9 MiB      kernel raw slot
16 MiB       p1 BOOT begins
```

## Kernel requirements

Для root-on-SD недостаточно `CONFIG_MMC=y`. Host controller и ext4 также должны
быть встроены:

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

`scripts/build_kernel.sh` выставляет и проверяет эти параметры перед сборкой.

## Разделы

| Раздел | Размер | FS | Назначение |
|---|---:|---|---|
| raw boot area | 16 MiB | — | SPL/U-Boot/env/kernel |
| p1 BOOT | 128 MiB | FAT32 | backup-копии boot artifacts, PegineLab assets, boot map |
| p2 ROOTFS | всё свободное до MEDIA | ext4 | Linux/userspace/settings |
| p3 MEDIA | 20 GiB | ext4 | recordings/snapshots/events |

## Первый power-on

Первый тест выполняется с UART 115200. Нужен лог с самого момента подачи питания.

Если BootROM не начинает читать SD, проверяются питание SD slot, GPIO/card-detect
и разводка конкретной платы. На некоторых Ingenic-камерах питание microSD
коммутируется GPIO; при физически отсутствующей flash это аппаратный вопрос,
а не повод возвращаться к SPI boot.

Определение image sensor остаётся задачей kernel/OS camera stack, а не ручным
этапом Web UI.
