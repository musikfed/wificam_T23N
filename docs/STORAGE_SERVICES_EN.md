# SD card, recordings and optional services

## SD is the only persistent boot/storage medium

This T23/T23N configuration has no external SPI/NOR flash.

| Area | Size | FS | Purpose |
|---|---:|---|---|
| raw boot | 16 MiB | — | SPL/U-Boot/env/uImage |
| p1 BOOT | 128 MiB | FAT32 | backup boot artifacts and PegineLab assets |
| p2 ROOTFS | remaining space before MEDIA | ext4 | Linux/apps/configs/VPN/SSH/logs |
| p3 MEDIA | 20 GiB | ext4 | recordings/snapshots/events |

A typical marketed 32 GB card leaves roughly 9 GiB for ROOTFS.

## Writing the card

Normal workflow:

```sh
sh scripts/build_all.sh
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS
sudo sh scripts/flash_full_firmware_sd.sh /dev/sdX
```

`prepare_sd.sh` is the low-level writer. It requires the T23N MMC bootloader,
kernel and a complete rootfs archive and normally should not be called directly.

MEDIA size can be overridden with `MEDIA_GIB`.

## MEDIA

`S90wificam` mounts the filesystem labeled `MEDIA` at `/mnt/media`:

```text
/mnt/media/
├── recordings/
├── snapshots/
└── events/
```

## Optional services

SSH, WireGuard and AmneziaWG remain disabled without marker files:

```text
/data/services/ssh.enabled
/data/services/wireguard.enabled
/data/services/amneziawg.enabled
```

VPN configuration lives under `/data/vpn`.

`S91wificam-services` starts only explicitly enabled services. The complete SD
rootfs disables the stock Dropbear auto-start so SSH remains genuinely optional.

Sensor discovery remains an OS camera-stack responsibility.
