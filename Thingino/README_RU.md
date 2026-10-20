# Thingino T23N SD + PegineLab WIFICAM

## Что является каноническим образом

Для текущего аппаратного теста используется прямой MMC/SD image:

```text
Thingino/thingino-t23-sd.bin
```

Это **не** `autoupdate-full.bin` для SPI/NOR. Образ записывается на всю SD
целиком и должен загрузиться при физически отсутствующей SPI/NOR.

Текущий профиль-кандидат:

```text
galayou_g2_t23n_sc2336_atbm6012bx
SoC    : T23N
sensor : SC2336
Wi-Fi  : ATBM6012BX
```

Почему выбран он: в локальной shell history найдено, что именно этот Thingino
профиль уже собирался ранее и готовый image копировался как
`/mnt/d/Thingino/thingino-t23-sd.bin`.

Это сильная зацепка, но **не доказательство**, что PCB
`GV-T23-PTZ-MAIN-V2.0` действительно имеет именно SC2336 + ATBM6012BX.
Окончательное подтверждение — загрузка и работа железа.

## Обязательная Web UI

PegineLab WIFICAM — не дополнительный файл «на потом», а обязательная часть
канонического image.

После успешной загрузки ожидается:

```text
Thingino Web UI       : http://CAMERA_IP/
PegineLab WIFICAM     : http://CAMERA_IP:8080/
```

WIFICAM включает:

- собственный HTML/CSS/JS интерфейс;
- CGI JSON API;
- реальный snapshot preview через Thingino `prudyntctl`;
- start/stop camera через Thingino `S31prudynt`;
- snapshot и recording;
- Wi-Fi status/config;
- storage status;
- optional SSH / WireGuard / AmneziaWG controls;
- persistent WIFICAM state под `/opt/wificam`.

Скрипт сборки **завершается ошибкой и не публикует image**, если WIFICAM не
найден внутри реального `rootfs.ext2`.

## Сборка и публикация образа

После одного обновления основного репозитория:

```sh
cd ~/myipcam/wificam_T23N
git pull
PUBLISH=1 sh scripts/build_thingino_wificam_image.sh
```

**Отдельно клонировать Thingino вручную больше не требуется.** Если каталога
нет, build-script создаст его сам.

Скрипт:

1. ищет Thingino checkout в `~/myipcam/thingino-firmware`,
   `~/thingino-firmware` или `~/myipcam/Thingino/thingino-firmware`;
2. если checkout отсутствует, **сам клонирует**
   `https://github.com/themactep/thingino-firmware.git` с submodules в
   `~/myipcam/thingino-firmware`;
3. checkout переводится на зафиксированный commit
   `9925f46f73b9c39ec8d2a65134b18c94e6fdfb97`, чтобы upstream не менялся
   между попытками;
4. собирает профиль `galayou_g2_t23n_sc2336_atbm6012bx`;
5. включает MMC0 1-bit boot;
6. задаёт root `/dev/mmcblk0p2`, ext4;
7. включает BusyBox httpd для отдельной WIFICAM на TCP 8080;
   Для минимальной PegineLab-админки проверяются только необходимые возможности:
   `CONFIG_HTTPD`, `CONFIG_FEATURE_HTTPD_CGI`,
   `CONFIG_FEATURE_HTTPD_BASIC_AUTH`, `CONFIG_FEATURE_HTTPD_AUTH_MD5`.
   Минимальные HTTP-флаги передаются через штатный Buildroot параметр
   `BR2_PACKAGE_BUSYBOX_CONFIG_FRAGMENT_FILES`. Это важно для pinned Thingino:
   его `BUSYBOX_KCONFIG_FRAGMENT_FILES += ...` затем перезаписывается в
   `package/busybox/busybox.mk`. Если FAST-build всё же содержит старый
   BusyBox `.config`, wrapper запускает `br-busybox-reconfigure`, проверяет
   четыре флага и затем заново формирует `rootfs.ext2`;
8. добавляет WIFICAM непосредственно в Buildroot rootfs overlay;
9. если `cleanbuild` не создал `rootfs.ext2`, явно запускает Buildroot target `rootfs-ext2`;
10. проверяет WIFICAM в build target и в самом `rootfs.ext2` через `debugfs`;
11. собирает настоящий SD disk image: DOS/MBR + pinned MMC U-Boot на LBA34 + FAT p1 + ext4 p2;
12. сохраняет его как `Thingino/thingino-t23-sd.bin`;
13. создаёт SHA256 и `Thingino/IMAGE_INFO.txt`;
14. при `PUBLISH=1` делает commit и push в текущую ветку.

Если существует исторический файл
`/mnt/d/Thingino/thingino-t23-sd.bin`, его размер и SHA256 также заносятся в
`IMAGE_INFO.txt` для сравнения происхождения образов.

## Ожидаемая разметка canonical MMC image

Текущий Thingino MMC builder создаёт:

```text
sector 0        DOS/MBR partition table + 55aa
sector 34       SPL / MSPL
sector 86       U-Boot proper
sector 2048     p1 FAT16 (16 MiB), /uImage
sector 34816    p2 ext4, Thingino rootfs + PegineLab WIFICAM
после image     пока не используется
```

U-Boot должен загрузить:

```text
mmc 0:1 /uImage
root=/dev/mmcblk0p2
rootfstype=ext4
```

## Запись на SD

Перед записью обязательно определить карту заново:

```sh
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS
```

Для текущего кардридера ожидается примерно:

```text
29.1G  SD/MMC/MS PRO  usb  RM=1
```

Системный WSL диск `/dev/sdd` не трогать.

Если карта снова определилась как `/dev/sde`:

```sh
sudo sh scripts/write_thingino_wificam_sd.sh /dev/sde
```

Подтверждение:

```text
THINGINO-WIFICAM:/dev/sde
```

Writer проверяет полный SHA readback, `55aa`, `MSPL` на LBA34,
p1 на LBA2048 и p2 на LBA34816.

## Первый аппаратный тест

После успешного writer:

```sh
sync
```

Полностью обесточить камеру, вставить SD, затем подать питание.

Критерии успеха этого этапа:

```text
1. Камера показывает признаки Linux boot.
2. Поднимается Thingino/Wi-Fi.
3. Доступна штатная Thingino Web UI.
4. ОБЯЗАТЕЛЬНО доступна PegineLab WIFICAM на :8080.
5. WIFICAM status API отвечает.
6. Snapshot preview работает при поднятом Prudynt.
```

Только после этого расширяем оставшееся место 32-ГБ карты под постоянные
данные/MEDIA. Низкоуровневую область boot/SPL/U-Boot при этом больше не меняем.

## Legacy recovery

Однораздельный FAT32 + LBA34 + `autoupdate-full.bin` сохранён как отдельный
диагностический сценарий:

```text
scripts/prepare_legacy_thingino_sd.sh
scripts/verify_legacy_thingino_sd.sh
```

Не смешивать его с canonical direct-MMC image. Это два разных эксперимента.
