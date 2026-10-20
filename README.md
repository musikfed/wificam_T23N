# wificam_T23N — autonomous SD firmware

![PegineLab](web/assets/peginelab-logo.svg)

Экспериментальная прошивка для Wi‑Fi камеры **Ingenic T23/T23N**, ветка
`mymarrchWFcam`.

## Аппаратный режим этой ветки

**SPI/NOR flash физически отсутствует.** Прошивка не рассчитывает на загрузчик,
kernel, rootfs или environment во внешней flash-памяти.

Полная цепочка загрузки находится на SD. Для этой платы сохраняется геометрия,
которая уже совпадает со старым рабочим Thingino installer path: обычный DOS/MBR
в sector 0, SPL/U-Boot в raw LBA 34 и первый FAT32-раздел с LBA 2048.

```text
T23 BootROM
   ↓
raw SD sector 34 (17 KiB)
SPL / MMC bootstrap (MSC0 1-bit)
   ↓
raw SD sector 86
upstream T23N MMC U-Boot
   ↓
p1 BOOT FAT32, start sector 2048 (1 MiB), /uImage
   ↓
/dev/mmcblk0p2
ext4 ROOTFS
   ↓
Thingino T23N userspace + mandatory PegineLab WIFICAM Web UI
```

Для этого используется точный upstream-образ
`u-boot-isvp_t23n_msc0_mmc1bit.bin` из
`gtxaspec/ingenic-u-boot-xburst1`, release `uboot-xb1-2025-09-11`.
Зафиксированный SHA-256: `4d4d4ff27acce1e5e59577c35ef98a505ae42a0bbb07583380463a81cdbfd6a5`.
`scripts/build_sd_bootloader.sh` теперь не пересобирает старое дерево OpenIPC,
а скачивает этот зафиксированный release asset и проверяет его размер, MSPL
magic и SHA-256.

Для T23N SD-bootstrap используется **MSC0 1-bit**. Raw offset остаётся тем же:
SPL начинается с sector 34 (17 KiB), U-Boot proper после 26 KiB SPL — с
sector 86. Upstream MMC U-Boot загружает kernel как `/uImage` из FAT32 p1
и передаёт root `/dev/mmcblk0p2`.

## Текущий основной путь / Current primary path

**Основной следующий образ этой ветки — прямой Thingino MMC/SD image, а не
`autoupdate-full.bin` и не OpenIPC-rootfs.**

История сборки на этом хосте показала ранее использованный профиль
`galayou_g2_t23n_sc2336_atbm6012bx` (T23N + SC2336 + ATBM6012BX). Пока это
**профиль-кандидат**, а не доказанная идентификация платы
`GV-T23-PTZ-MAIN-V2.0`.

Canonical artifact:

```text
Thingino/thingino-t23-sd.bin
Thingino/thingino-t23-sd.bin.sha256
Thingino/IMAGE_INFO.txt
```

Он собирается скриптом:

```sh
cd ~/myipcam/wificam_T23N
git pull
PUBLISH=1 sh scripts/build_thingino_wificam_image.sh
```

Отдельный ручной clone Thingino не требуется: если checkout отсутствует,
скрипт сам клонирует upstream с submodules в
`~/myipcam/thingino-firmware` и фиксирует его на commit
`9925f46f73b9c39ec8d2a65134b18c94e6fdfb97`.

Скрипт не публикует образ, если не доказано, что PegineLab WIFICAM реально
находится внутри `p2/rootfs.ext2`. Проверяются `index.html`, init-script,
CGI API, snapshot CGI и наличие BusyBox `httpd`.

Web UI является **обязательным acceptance criterion**:

```text
Thingino UI          : http://CAMERA_IP/   (или HTTPS, если включён Thingino TLS)
PegineLab WIFICAM    : http://CAMERA_IP:8080/
```

The canonical image is a **direct MMC/SD disk image**. It is written to the
whole SD card and boots `uImage` from p1 with ext4 root on
`/dev/mmcblk0p2`. It is **not** an SPI/NOR autoupdate payload.

Русская инструкция: `Thingino/README_RU.md`  
English instructions: `Thingino/README_EN.md`

## Разметка SD

Первый 1 MiB оставлен под MBR, SPL/U-Boot и environment; p1 начинается с sector 2048.

| Область | Положение | Назначение |
|---|---:|---|
| DOS/MBR | sector 0 | таблица разделов |
| SPL/U-Boot image | sector 34 | вход BootROM, MMC SPL |
| U-Boot proper | sector 86 | вычисляется из 26 KiB SPL |
| U-Boot env | sector 546 (`0x44400`) | 32 KiB environment |
| uImage | p1 `BOOT:/uImage` | активный kernel boot source |
| p1 BOOT | с 1 MiB (sector 2048), 128 MiB, FAT32 | активный uImage, копия U-Boot, logo, jingle, boot map |
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

### Почему разметка p1 не стирает U-Boot

Создание BOOT-раздела не может затереть raw U-Boot в этой схеме:

- SPL/U-Boot начинается с LBA 34;
- точный upstream binary имеет 189685 байт и занимает LBA 34..404;
- p1 начинается только с LBA 2048.

Кроме того, `prepare_sd.sh` записывает U-Boot **после** создания/форматирования
разделов, а `verify_sd_firmware.sh` затем читает raw LBA34 обратно и сравнивает
полный SHA-256 с исходным файлом. Если в выводе есть
`Raw SPL/U-Boot SHA256 = 4d4d4ff...`, версия «разделы затёрли LBA34» уже
исключена; искать нужно раньше/ниже по цепочке BootROM/SD bootstrap или в выборе
профиля MMC.

Важно: `autoupdate-full.bin` остаётся только историческим recovery/install
маршрутом. Для текущего основного теста при физически отсутствующей SPI/NOR
используется прямой Thingino MMC image: raw SD bootstrap + `p1:/uImage` +
ext4 `/dev/mmcblk0p2`. Никакая запись в SPI для этого пути не требуется.

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

## Windows + WSL: подключение SD-кардридера

Команда `usbipd` относится к **Windows host**, а не к Ubuntu/WSL. Если в
Ubuntu появляется `Command 'usbipd' not found`, не устанавливайте
`linux-tools-common`: это другой пакет и он не подключает USB-устройство к
WSL.

Порядок:

1. В **Windows PowerShell**:
   ```powershell
   usbipd list
   ```
2. Найдите USB-кардридер и его текущий `BUSID`.
3. Если устройство ещё не `Shared`, в PowerShell от администратора:
   ```powershell
   usbipd bind --busid <BUSID>
   ```
4. Подключите его к WSL:
   ```powershell
   usbipd attach --wsl --busid <BUSID>
   ```
5. После успешного `usbipd attach --wsl ...` вернитесь в уже открытый Ubuntu/WSL и **сразу** выполните:
   ```sh
   lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS
   ```

Подтверждённый на этом хосте порядок такой:

```text
Windows PowerShell:
  usbipd list
  usbipd bind --busid BUSID      # только если ещё не Shared
  usbipd attach --wsl --busid BUSID

Ubuntu/WSL:
  lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS
```

Не запускайте `wsl --mount ...` внутри Ubuntu: `wsl.exe` — Windows-команда.
Ошибка `Command 'wsl' not found` внутри Ubuntu ничего не подключает, и ставить
`sudo apt install wsl` ради этого не нужно.

После каждого detach/attach имя SD может измениться. Писать можно только на
диск, который совпадает по размеру/модели/USB/RM=1. Системный WSL-диск трогать
нельзя. Старые разделы `BOOT/ROOTFS/MEDIA` после подключения допустимы:
recovery-скрипт сам переразметит карту.

## Legacy fallback — исторический Thingino installer path

Этот сценарий сохранён как **отдельный fallback/диагностика**, если canonical
direct-MMC Thingino image не стартует. Он больше не является основным путём и
не должен смешиваться с `Thingino/thingino-t23-sd.bin`.

Точная геометрия:

```text
sector 0          DOS/MBR
sector 34..404    raw u-boot-isvp_t23n_msc0_mmc1bit.bin
sector 2048       p1 BOOT FAT32, ровно 128 MiB
BOOT:/            autoupdate-full.bin
после p1          UNALLOCATED
```

Ключевой порядок: сначала создаётся/форматируется один 128 MiB FAT32-раздел,
**затем** U-Boot пишется на весь диск raw-командой с `bs=512 seek=34`.
Файл U-Boot не копируется в FAT вместо raw-записи.

Для WSL/Linux используется один скрипт:

```sh
sudo sh scripts/prepare_legacy_thingino_sd.sh /dev/sdX /полный/путь/autoupdate-full.bin
```

Скрипт сам:

- удаляет предыдущую разметку в начале карты;
- создаёт только p1 FAT32 128 MiB с LBA 2048;
- оставляет всё остальное место неразмеченным;
- форматирует p1 как `BOOT`;
- после форматирования пишет точный pinned U-Boot в raw LBA34;
- проверяет MBR `55aa`, magic `MSPL`, полный SHA-256 raw U-Boot;
- копирует `autoupdate-full.bin` в корень BOOT и проверяет его SHA-256.

Не переименовывать случайный firmware-файл в `autoupdate-full.bin`: для этого
этапа нужен именно тот Thingino installer payload, который предназначен для
этого механизма.

Отдельно: в актуальном upstream `sdupdate` видны операции с SPI
(`sf erase/sf write`). Это не отменяет исторический факт загрузки этой платы
через такой SD layout, но означает, что после восстановления ранней загрузки
надо отдельно выяснить, какой именно payload/версия обеспечивал работу без
внешней SPI.

Подробная пошаговая инструкция: `docs/THINGINO_RECOVERY_SD_RU.md`.

## Этап 2 — экспериментальный полный SD-root

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
- кладёт активный kernel как `BOOT:/uImage`;
- проверяет `BOOT:/uImage` по SHA-256;
- распаковывает Linux в p2;
- создаёт MEDIA p3.

Этот сценарий сейчас **не запускать до успешного Этапа 1**. Он остаётся экспериментальным до подтверждения раннего BootROM → SD → SPL на реальной плате.

## Root filesystem

Для **основного текущего пути** база userspace — Thingino для
`galayou_g2_t23n_sc2336_atbm6012bx`, дополненный PegineLab WIFICAM прямо в
`rootfs.ext2`. Старый OpenIPC SD-root путь сохранён как экспериментальный и
не является текущим аппаратным тестом.

WIFICAM добавляет Web UI/API, отдельный httpd на TCP 8080, управление Wi‑Fi,
storage, optional SSH/WireGuard/AmneziaWG и интеграцию с Thingino Prudynt для
status/start/stop, snapshot и recording.

Sensor detection не выполняется Web UI: сенсор и камера должны
инициализироваться Thingino/kernel camera stack.

## PegineLab boot branding

В rootfs:

- PegineLab logo;
- оригинальный ~7 s 8-bit/chiptune WAV;
- ранний `S05peginelab-boot`.

Splash/audio запускаются неблокирующе. Они появятся только если camera Linux
userspace имеет рабочий framebuffer/audio player. Копии logo/jingle также лежат
на p1 BOOT, но T23 BootROM их сам не отображает и не проигрывает.

## Web

После успешной загрузки canonical Thingino image и получения IP:

```text
Thingino:          http://CAMERA_IP/
PegineLab WIFICAM: http://CAMERA_IP:8080/
```

WIFICAM на первом локальном запуске позволяет задать Web password, затем
перезапускается с authentication.

SSH, WireGuard и AmneziaWG по умолчанию выключены. Persistent marker-файлы
WIFICAM хранятся под `/opt/wificam/services/`.

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
scripts/write_verify_sd_bootloader.sh
rootfs/
web/
docs/
```
