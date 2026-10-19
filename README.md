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
SPL / MMC bootstrap (MSC0 1-bit)
   ↓
raw SD sector 86
upstream T23N MMC U-Boot
   ↓
p1 BOOT (FAT32) /uImage
   ↓
/dev/mmcblk0p2
ext4 ROOTFS
   ↓
OpenIPC T23 userspace + WIFICAM/PegineLab
```

Для этого используется точный upstream-образ
`u-boot-isvp_t23n_msc0_mmc1bit.bin` из
`gtxaspec/ingenic-u-boot-xburst1`, release `uboot-xb1-2025-09-11`.
`scripts/build_sd_bootloader.sh` теперь не пересобирает старое дерево OpenIPC,
а скачивает этот зафиксированный release asset и проверяет его размер, MSPL
magic и SHA-256.

Для T23N SD-bootstrap используется **MSC0 1-bit**. Raw offset остаётся тем же:
SPL начинается с sector 34 (17 KiB), U-Boot proper после 26 KiB SPL — с
sector 86. Upstream MMC U-Boot загружает kernel как `/uImage` из FAT32 p1
и передаёт root `/dev/mmcblk0p2`.

## Разметка SD

Первые 16 MiB не принадлежат ни одному filesystem-разделу: это raw boot area.

| Область | Положение | Назначение |
|---|---:|---|
| MBR | sector 0 | таблица разделов |
| SPL/U-Boot image | sector 34 | вход BootROM, MMC SPL |
| U-Boot proper | sector 86 | вычисляется из 26 KiB SPL |
| U-Boot env | sector 546 (`0x44400`) | 32 KiB environment |
| uImage | p1 `BOOT:/uImage` | активный kernel boot source |
| raw uImage backup | sector `0x1800` | резервная копия; upstream U-Boot её не читает |
| p1 BOOT | с 16 MiB, 128 MiB, FAT32 | копии uImage/U-Boot, logo, jingle, boot map |
| p2 ROOTFS | всё свободное до MEDIA, ext4 | Linux/userspace/configs |
| p3 MEDIA | 20 GiB, ext4 | recordings/snapshots/events |

Upstream MMC U-Boot использует FAT boot path:

```text
root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait init=/init
mmc rescan
fatload mmc 0:1 ${baseaddr} uImage
bootm ${baseaddr}
```

MMC environment находится по `0x44400` (sector 546), размер 32 KiB.

Важно: `autoupdate-full.bin` — это механизм установки/обновления Thingino,
который обычно переносит firmware во внутреннюю flash. В режиме этой ветки
SPI/NOR физически отсутствует, поэтому `autoupdate-full.bin` не является
постоянной ОС и не нужен для загрузки. Постоянная SD-only схема здесь —
upstream MMC U-Boot + `BOOT:/uImage` + ext4 `/dev/mmcblk0p2`.

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
2. получает и проверяет pinned upstream **T23N SD SPL/U-Boot MSC0 1-bit**;
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
- кладёт активный kernel как `BOOT:/uImage` и дополнительно сохраняет raw backup в sector `0x1800`;
- проверяет `BOOT:/uImage` и резервный raw kernel readback по SHA-256;
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

После `SD FIRMWARE VERIFY: OK`:

1. полностью обесточить камеру;
2. вставить SD;
3. подать питание.

В этой ветке основной сценарий — автономная загрузка **только с SD** при
физически отсутствующей SPI/NOR. UART не является частью обязательного
процесса записи или проверки карты.

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
