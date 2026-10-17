# T23/T23N hardware: SD-only boot

## Hardware state

The target camera uses **Ingenic T23/T23N** and the external SPI/NOR flash is
**physically removed**. The project therefore must not depend on a bootloader,
environment, kernel or root filesystem stored in external flash.

The SD card is the only persistent boot medium.

## Boot chain

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

The T23 MMC U-Boot path reads the kernel with:

```text
mmc read 0x80600000 0x1800 0x3000
bootm 0x80600000
```

Our T23N MMC build supplies:

```text
root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait init=/init
```

## Raw boot reserve

The first 16 MiB is not a filesystem partition because BootROM/SPL/U-Boot and
the raw kernel use fixed sectors.

```text
0            MBR
17 KiB       combined SPL/U-Boot image
43 KiB       U-Boot proper (sector 86)
257 KiB      U-Boot environment (sector 514)
3 MiB        raw uImage
3–9 MiB      raw kernel slot
16 MiB       p1 BOOT starts
```

## Kernel requirements

Direct SD root requires these features built into the kernel, not modules:

```text
CONFIG_MMC=y
CONFIG_MMC_BLOCK=y
CONFIG_JZMMC_V12=y
CONFIG_JZMMC_V12_MMC0=y
CONFIG_EXT4_FS=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
```

`scripts/build_kernel.sh` sets and verifies them.

## Partitions

| Area | Size | FS | Purpose |
|---|---:|---|---|
| raw boot area | 16 MiB | — | SPL/U-Boot/env/kernel |
| p1 BOOT | 128 MiB | FAT32 | backup boot artifacts and PegineLab assets |
| p2 ROOTFS | remaining space before MEDIA | ext4 | Linux/userspace/settings |
| p3 MEDIA | 20 GiB | ext4 | recordings/snapshots/events |

## First power-on

Capture UART at 115200 from the instant power is applied. If BootROM does not
read the SD card, investigate SD-slot power, GPIO/card-detect and board routing.
Some Ingenic camera boards switch microSD power through a GPIO.

Sensor identification remains an OS/kernel camera-stack responsibility, not a
manual Web UI step.
