# T23/T23N hardware: SD-only boot

## Hardware state

The target camera uses **Ingenic T23/T23N** and the external SPI/NOR flash is
**physically removed**. The project must not depend on a bootloader,
environment, kernel or root filesystem stored in external flash.

The SD card is the only persistent boot medium.

## Boot chain

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

The exact upstream `u-boot-isvp_t23n_msc0_mmc1bit.bin` is used. Its normal
kernel path is:

```text
mmc rescan
fatload mmc 0:1 ${baseaddr} uImage
bootm ${baseaddr}
```

Root:

```text
root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait init=/init
```

## First 16 MiB

```text
0             MBR
17 KiB        combined SPL/U-Boot image (sector 34)
43 KiB        U-Boot proper (sector 86)
273 KiB       U-Boot env (sector 546 / 0x44400)
3 MiB         redundant raw uImage copy
16 MiB        p1 BOOT begins; /uImage is the active kernel
```

The raw image at sector `0x1800` is only a verified backup. Upstream U-Boot's
normal boot path does not read it.

## Kernel requirements

Direct SD root requires these features built into the kernel:

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

## Partitions

| Area | Size | FS | Purpose |
|---|---:|---|---|
| raw boot area | 16 MiB | — | SPL/U-Boot/env + raw backup |
| p1 BOOT | 128 MiB | FAT32 | active /uImage, U-Boot copy, branding |
| p2 ROOTFS | remaining space before MEDIA | ext4 | Linux/userspace/settings |
| p3 MEDIA | 20 GiB | ext4 | recordings/snapshots/events |

## First power-on

After complete offline SD verification, fully power off the camera, insert the
card, then apply power. UART is not a mandatory part of this workflow.

If BootROM does not begin reading the SD card, investigate SD-slot power,
card-detect/strap state and board routing. With SPI/NOR physically absent this
is an early hardware boot-path issue, not a reason to fall back to SPI boot.
