# Board compatibility and safe validation

## Target hardware

This build targets **Ingenic T23/T23N** cameras using MIPS/XBurst and Linux 3.10.x.

A board is finally validated only after UART/U-Boot boot testing plus RAM, flash, Wi-Fi and GPIO checks. Sensor identification is not a manual Web UI step: the OS drivers/camera userspace should discover and initialize the camera during boot.

## Before removing or disabling SPI flash

Prefer reversible UART/SD boot first.

1. Dump the original flash.
2. Store copies and SHA-256 hashes.
3. Record flash marking and voltage.
4. Save U-Boot `printenv` and boot log.
5. Do not erase factory flash until SD/RAM boot succeeds.

## U-Boot

```text
version
printenv
bdinfo
mmc list
part list mmc 0
help fatload
help ext4load
help bootm
```

## Current SD layout

| Partition | Size | FS | Purpose |
|---|---:|---|---|
| p1 BOOT | 128 MiB | FAT32 | `uImage`, boot files |
| p2 ROOTFS | all remaining space | ext4 | Linux, applications, settings, VPN, SSH, logs |
| p3 MEDIA | 20 GiB | ext4 | camera video, photos and events |

`scripts/prepare_sd.sh` computes ROOTFS automatically from card size minus BOOT, 20 GiB MEDIA and a small alignment reserve.

MEDIA:

```text
/mnt/media/
├── recordings/
├── snapshots/
└── events/
```

Wi-Fi, web authentication, VPN configs and service marker files live under `/data` inside the large ROOTFS.

## First boot

Load `uImage` from SD into RAM and execute `bootm` without modifying the factory flash.
