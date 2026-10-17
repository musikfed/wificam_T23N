# SD-карта, запись и optional services

## SD — единственный persistent storage

Для этой T23/T23N конфигурации внешняя SPI/NOR отсутствует. SD содержит raw
boot area, Linux rootfs и media.

| Область | Размер | FS | Назначение |
|---|---:|---|---|
| raw boot | 16 MiB | — | SPL/U-Boot/env/uImage |
| p1 BOOT | 128 MiB | FAT32 | backup boot artifacts + PegineLab assets |
| p2 ROOTFS | всё свободное до MEDIA | ext4 | Linux, apps, configs, VPN, SSH, logs |
| p3 MEDIA | 20 GiB | ext4 | recordings, snapshots, events |

На типичной 32 GB карте p2 получается примерно 9 GiB.

## Запись

Основной сценарий:

```sh
sh scripts/build_all.sh
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS
sudo sh scripts/flash_full_firmware_sd.sh /dev/sdX
```

`prepare_sd.sh` является внутренним низкоуровневым writer и требует сразу
T23N MMC bootloader, kernel и complete rootfs archive:

```sh
sudo sh scripts/prepare_sd.sh /dev/sdX --yes \
  out/u-boot-t23n-sd.bin \
  ~/myipcam/build/kernel/arch/mips/boot/uImage \
  complete-rootfs.tar.gz
```

Обычно вызывать его напрямую не нужно.

Размер MEDIA можно переопределить:

```sh
MEDIA_GIB=20 sudo -E sh scripts/flash_full_firmware_sd.sh /dev/sdX
```

## MEDIA

После boot `S90wificam` монтирует label `MEDIA` в `/mnt/media`.

```text
/mnt/media/
├── recordings/
├── snapshots/
└── events/
```

## Optional services

SSH, WireGuard и AmneziaWG не должны запускаться постоянно, если отключены.

Markers:

```text
/data/services/ssh.enabled
/data/services/wireguard.enabled
/data/services/amneziawg.enabled
```

VPN configs:

```text
/data/vpn/wg0.conf
/data/vpn/awg0.conf
```

`S91wificam-services` запускает только сервисы с marker-файлами. В полном
SD rootfs штатный auto-start Dropbear отключается, чтобы SSH оставался
действительно optional.

Sensor identification остаётся задачей OS camera stack.
