# Thingino T23N SD + PegineLab WIFICAM

## Статус 0.1_test

**АППАРАТНО ПОДТВЕРЖДЕНО 2026-10-21.** Канонический
`Thingino/thingino-t23-sd.bin` успешно записан на SD, прошёл полный readback
SHA256/MBR/MSPL/partition verification и загрузился на целевой камере.
Загрузка SD подтверждена. Runtime-доступ PegineLab WIFICAM на `:8090` проверяется отдельно.

Зафиксированный SHA256:

```text
f9f50a8595d4fe629ed787483188319000d2780bd3c6dee56fef4de5e754f6be
```


## Что является каноническим образом

Для текущего аппаратного теста используется прямой MMC/SD image:

```text
Thingino/thingino-t23-sd.bin
```

Это **не** `autoupdate-full.bin` для SPI/NOR. Образ записывается на всю SD
целиком и должен загрузиться при физически отсутствующей SPI/NOR.

Аппаратно подтверждённый профиль:

```text
galayou_g2_t23n_sc2336_atbm6012bx
SoC    : T23N
sensor : SC2336
Wi-Fi  : ATBM6012BX
```

Почему выбран он: в локальной shell history найдено, что именно этот Thingino
профиль уже собирался ранее и готовый image копировался как
`/mnt/d/Thingino/thingino-t23-sd.bin`.

Аппаратный тест 2026-10-21 подтвердил загрузку этого профиля на целевой камере.

## Порт PegineLab WIFICAM

Проверка на реальной камере показала, что **TCP 8080 уже используется
штатным Thingino camera/API stack**. Поэтому PegineLab WIFICAM работает на
**TCP 8090**. Это userspace-настройка BusyBox `httpd`; ядро для смены порта
пересобирать не нужно.

Для уже загруженной камеры достаточно изменить `WEB_PORT` в
`/etc/wificam/wificam.conf` и перезапустить `S90wificam`.

## Обязательная Web UI

PegineLab WIFICAM — не дополнительный файл «на потом», а обязательная часть
канонического image. При этом штатная Thingino UI и PegineLab WIFICAM — это
**две разные веб-службы**.

После успешной загрузки:

```text
Thingino stock UI     : http://CAMERA_IP/ или https://CAMERA_IP/
Thingino login        : root
Thingino password     : root

PegineLab WIFICAM     : http://CAMERA_IP:8090/
```

Если браузер показывает `https://CAMERA_IP/login.html` с логотипом Thingino,
это нормальная штатная Thingino Web UI. Для PegineLab нужно явно открыть
`http://CAMERA_IP:8090/`.

Первый запуск WIFICAM настроен как локальный bootstrap без аутентификации:
`ALLOW_UNAUTHENTICATED_WEB=1`. После задания пароля WIFICAM перезапускается
с Basic Auth; имя пользователя по умолчанию для установки пароля — `admin`.

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
7. включает BusyBox httpd для отдельной WIFICAM на TCP 8090;
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

В WSL2 USB-кардридер сначала нужно передать из Windows в WSL. Команды
`usbipd` выполняются **в Windows PowerShell от имени администратора**, не
внутри Ubuntu/WSL:

```powershell
usbipd list
usbipd bind --busid <BUSID>
usbipd attach --wsl --busid <BUSID>
```

`<BUSID>` берётся только из реального вывода `usbipd list` для нужного
кардридера; примерный номер нельзя подставлять вслепую.

Проверенный пример для текущего Acer/Realtek кардридера:

```text
Windows usbipd list:
BUSID 3-2
VID:PID 0bda:0177
DEVICE Realtek USB 2.0 Card Reader
STATE Shared
```

Если состояние уже `Shared`, повторный `bind` не нужен; достаточно в
Windows PowerShell:

```powershell
usbipd attach --wsl --busid 3-2
```

После успешного attach текущий reader подтверждён в WSL так:

```text
lsusb:
0bda:0177 Realtek Semiconductor Corp. USB2.0-CRW

lsblk:
sde    /dev/sde   29.1G  SD/MMC/MS PRO  usb  RM=1
└─sde1 /dev/sde1 128M   BOOT  vfat
```

Имя `/dev/sde` подтверждено только для этой конкретной сессии. После
переподключения всё равно снова сверять размер, MODEL, `TRAN=usb` и `RM=1`.

После attach в WSL обязательно определить карту заново:

```sh
lsusb
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS
```

Для текущей карты ожидается примерно 29.1 GiB, `TRAN=usb`, `RM=1`.
Системные WSL Virtual Disk не трогать.

**Критично про смещение:** `Thingino/thingino-t23-sd.bin` — полный disk
image. Его всегда записывают с **LBA0 / byte 0**, без `seek=`. Нужное
смещение загрузчика уже находится внутри файла:

```text
LBA0      MBR
LBA34     SPL/MSPL
LBA86     U-Boot proper
LBA2048   p1 FAT16 /uImage
LBA34816  p2 ext4 rootfs
```

Если карта определилась, например, как `/dev/sde`:

```sh
sudo sh scripts/write_thingino_wificam_sd.sh /dev/sde
```

Подтверждение:

```text
THINGINO-WIFICAM:/dev/sde
```

Writer **до записи** проверяет sidecar SHA256, MBR `55aa`, MSPL на LBA34 и
старты p1/p2 в самом image. Затем пишет весь image с LBA0 и после записи
проверяет полный SHA readback, `55aa`, `MSPL` на LBA34, p1 на LBA2048 и
p2 на LBA34816. Ручной `dd ... seek=34` для готового
`thingino-t23-sd.bin` запрещён: он сдвинет весь disk image и сломает MBR.

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
3. Доступна штатная Thingino Web UI; default login root/root.
4. Отдельно открыть http://CAMERA_IP:8090/ — это PegineLab WIFICAM.
5. WIFICAM status API отвечает.
6. Snapshot preview работает при поднятом Prudynt.
```

Если открывается только штатный Thingino, а `:8090` не отвечает, это не
ошибка SD boot. Проверять нужно именно сервис WIFICAM:

```sh
ps | grep '[h]ttpd'
cat /var/log/wificam-httpd.log
/etc/init.d/S90wificam restart
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
