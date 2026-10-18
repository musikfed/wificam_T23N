# wificam_T23N — autonomous SD firmware

![PegineLab](web/assets/peginelab-logo.svg)

Экспериментальная прошивка для Wi‑Fi камеры **Ingenic T23/T23N**, ветка
`mymarrchWFcam`.

## Аппаратный режим этой ветки

**SPI/NOR flash физически отсутствует.** Прошивка не рассчитывает на загрузчик,
kernel, rootfs или environment во внешней flash-памяти.

Полная цепочка загрузки должна находиться на SD:

```text
T23 BootROM
   ↓
raw SD sector 34 (17 KiB)
SPL / MMC bootstrap
   ↓
raw SD sector 86
U-Boot T23N MMC
   ↓
raw SD sector 0x1800 (3 MiB)
uImage, raw slot 0x3000 sectors = 6 MiB
   ↓
/dev/mmcblk0p2
ext4 ROOTFS
   ↓
OpenIPC T23 userspace + WIFICAM/PegineLab
```

Для этого **нельзя** использовать обычный U-Boot, собранный для SPI/SFC.
`scripts/build_sd_bootloader.sh` собирает отдельный T23N MMC/SPL loader.

## Разметка SD

Первые 16 MiB не принадлежат ни одному filesystem-разделу: это raw boot area.

| Область | Положение | Назначение |
|---|---:|---|
| MBR | sector 0 | таблица разделов |
| SPL/U-Boot image | sector 34 | вход BootROM, MMC SPL |
| U-Boot proper | sector 86 | вычисляется из 26 KiB SPL |
| U-Boot env | sector 514 | 32 KiB environment |
| uImage | sector `0x1800` | kernel, raw read slot 6 MiB |
| p1 BOOT | с 16 MiB, 128 MiB, FAT32 | копии uImage/U-Boot, logo, jingle, boot map |
| p2 ROOTFS | всё свободное до MEDIA, ext4 | Linux/userspace/configs |
| p3 MEDIA | 20 GiB, ext4 | recordings/snapshots/events |

U-Boot для MMC использует:

```text
root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait init=/init
mmc read 0x80600000 0x1800 0x3000
bootm 0x80600000
```

## Сборка

Host-пакеты для Ubuntu/WSL:

```sh
sudo apt install -y git make gcc python3 curl squashfs-tools dosfstools fdisk e2fsprogs lzop
```

Собрать всё:

```sh
cd ~/myipcam/wificam_T23N
git switch mymarrchWFcam
git pull
sh scripts/build_all.sh
```

`build_all.sh` выполняет три шага:

1. пересобирает Linux kernel с **MMC controller + MMC block + EXT4 встроенными (=y)**;
2. собирает специальный **T23N SD SPL/U-Boot**;
3. пакует WIFICAM/PegineLab overlay.

Основные artifacts:

```text
~/myipcam/build/kernel/arch/mips/boot/uImage
out/u-boot-t23n-sd.bin
out/wificam-rootfs-overlay.tar.gz
```

Старый kernel hash из сборки до SD-only перехода не является deployable reference:
после включения built-in MMC/ext4 kernel должен быть пересобран и получит новый SHA-256.

## Полная запись SD

Сначала всегда проверить имя карты:

```sh
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS
```

Затем:

```sh
sudo sh scripts/flash_full_firmware_sd.sh /dev/sdX
```

Скрипт:

- требует специальный `out/u-boot-t23n-sd.bin`;
- проверяет, что kernel config содержит built-in MMC/ext4;
- скачивает и SHA-256 проверяет официальный OpenIPC T23 lite userspace bundle;
- добавляет WIFICAM/PegineLab overlay;
- **полностью переразмечает SD**;
- пишет SPL/U-Boot в raw sector 34;
- пишет kernel в raw sector `0x1800`;
- проверяет raw kernel readback по SHA-256;
- распаковывает Linux в p2;
- создаёт MEDIA p3.

Это единственный основной flash-сценарий для данной ветки.

## Root filesystem

База userspace — официальный OpenIPC T23 lite rootfs. Поверх него добавляются:

- PegineLab Web UI;
- `S05peginelab-boot`;
- WIFICAM service layer;
- Wi‑Fi management;
- MEDIA mount;
- optional SSH/WireGuard/AmneziaWG controls.

Sensor detection не выполняется вручную Web UI: камера и sensor должны
инициализироваться kernel/OS camera stack.

## PegineLab boot branding

В rootfs:

- PegineLab logo;
- оригинальный ~7 s 8-bit/chiptune WAV;
- ранний `S05peginelab-boot`.

Splash/audio запускаются неблокирующе. Они появятся только если camera Linux
userspace имеет рабочий framebuffer/audio player. Копии logo/jingle также лежат
на p1 BOOT, но T23 BootROM их сам не отображает и не проигрывает.

## Web

После успешной загрузки и получения IP:

```text
OpenIPC/Majestic: http://CAMERA_IP/
WIFICAM:          http://CAMERA_IP:8080/
```

WIFICAM на первом локальном запуске позволяет задать Web password, затем
перезапускается с authentication.

SSH, WireGuard и AmneziaWG по умолчанию выключены. Их marker-файлы:

```text
/data/services/ssh.enabled
/data/services/wireguard.enabled
/data/services/amneziawg.enabled
```

## MEDIA

```text
/mnt/media/
├── recordings/
├── snapshots/
└── events/
```

## Первый запуск платы

После записи SD:

1. полностью обесточить камеру;
2. вставить SD;
3. подключить UART 115200;
4. подать питание;
5. сохранить вывод **с первой строки BootROM/SPL/U-Boot**.

При отсутствии SPI/NOR первым проверяется именно SD BootROM path. На некоторых
платах слот SD может питаться через GPIO; если BootROM не видит карту, это
проверяется по UART и схеме платы, а не заменяется загрузкой из отсутствующей
flash.

## Основные файлы

```text
scripts/build_kernel.sh
scripts/build_sd_bootloader.sh
scripts/flash_full_firmware_sd.sh
scripts/prepare_sd.sh
patches/u-boot-ingenic-t23n-sd.patch
rootfs/
web/
docs/
```
