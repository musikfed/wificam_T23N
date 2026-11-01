# Acer WSL → персональная SD-карта T23N (без SPI/NOR)

> **Статус 2026-11-01:** инструкция по исходникам, НЕ подтверждение, что ноутбук Acer сейчас подключён к инструментам ChatGPT или что новая карта уже записана. Все команды WSL/USB/SD выполняет пользователь на своём Acer. Релиз `0.1_test` неизменен. Новый образ с настройками Wi-Fi **не публиковать**.

## 0. Критически важное загрузочное смещение

SPI/NOR микросхема **физически отпаяна**. Камера стартует именно из MMC/SD
BootROM: LBA 0 = MBR, LBA 34 = MSPL/SPL (сигнатура `4d53504c`),
LBA 86 = U-Boot proper, LBA 546 = резерв MMC environment,
LBA 2048 = BOOT FAT16 с `/uImage` (16 МиБ),
LBA 34816 = ROOTFS ext4 с PegineLab и SSH.
Профиль `galayou_g2_t23n_sc2336_atbm6012bx`, root `/dev/mmcblk0p2`.
Полный `thingino-t23-sd.bin` записывать **с самого LBA 0**, НИКОГДА
не добавлять `seek=34` к готовому образу.
Используются неизменённые проверенные загрузочные скрипты
`scripts/build_sd_bootloader.sh`,
`scripts/assemble_thingino_wificam_sd_image.sh`,
`scripts/write_thingino_wificam_sd.sh`.

## 1. Найти старые проекты и исходники (только чтение)

PowerShell Windows 11:

```powershell
wsl -l -v
usbipd list
Get-Disk | Select-Object Number,FriendlyName,BusType,Size
```

**НЕ** удалять ни один диск, раздел или каталог пока не проверены
текущие исходники, бинарные образы, незакоммиченные файлы и настройки.

Ubuntu 24.04 в WSL (владелец хранит дистрибутив на Windows D:):

```sh
ls -lah ~/myipcam ~/myipcam/wificam_T23N ~/myipcam/thingino-firmware 2>/dev/null
df -h ~
lsblk -o NAME,PATH,SIZE,MODEL,TRAN,RM,MOUNTPOINTS
```

Если проект уже есть:

```sh
cd ~/myipcam/wificam_T23N
sh scripts/wsl_camera_inventory.sh
git status --short --branch
```

Проверяющий скрипт **ничего не удаляет**. Старые каталоги с неизвестными
изменениями сперва сохранять и переносить в `~/myipcam/archive/`
с уникальным именем; не использовать `rm -rf ~/myipcam`.
После загрузки новой SD карты и резервирования своих файлов уже
можно вручную убирать подтверждённые дубликаты (не кешы наугад).

## 2. Клонировать репозиторий, если локальной копии нет

```sh
mkdir -p ~/myipcam
if [ ! -e ~/myipcam/wificam_T23N ]; then
  git clone --branch mymarrchWFcam \
    https://github.com/musikfed/wificam_T23N.git \
    ~/myipcam/wificam_T23N
fi
cd ~/myipcam/wificam_T23N
sh scripts/wsl_restore_camera.sh
sh scripts/wsl_camera_inventory.sh
```

Восстановление проверяет `origin`, не стирает каталог, отказывается
перезаписывать незакоммиченные изменения и делает только fast-forward.
Скрипт сборки сам клонирует отсутствующий Thingino в
`~/myipcam/thingino-firmware` и фиксирует его на
`9925f46f73b9c39ec8d2a65134b18c94e6fdfb97`.

## 3. Личный «секретный» Wi-Fi файл (не в Git!)

Подойдёт домашняя/лабораторная сеть 2.4 ГГц, WPA2-Personal/AES.
**ATBM6012BX не стоит пытаться подключать к сети только 5 ГГц или
WPA3-only.** Используйте существующую сеть без перенастройки AP.

В WSL:

```sh
cd ~/myipcam/wificam_T23N
cp local/wifi.env.example local/wifi.env
chmod 600 local/wifi.env
nano local/wifi.env
```

В файле изменить только значения:

```ini
WIFI_SSID="МОЯ_СЕТЬ_2_4_GHZ"
WIFI_PASSWORD="МОЙ_ПАРОЛЬ_WPA2"
```

Значения — **JSON-строки в двойных кавычках**. Для кавычки внутри
пароля используется `\"`, для обратного слеша `\\`.
Имя SSID: максимум 32 байта UTF-8, пароль WPA2: 8–63 печатных ASCII.
Не присылать этот файл в чат и не делать скриншоты с паролем!

`local/wifi.env` игнорируется Git; `local/wifi.env.example` содержит
только вымышленные данные и может находиться в публичном репозитории.
Генератор `scripts/prepare_wifi_overlay.py` **не выполняет** содержимое
секретного файла как shell-код; перед сборкой создаёт
`/etc/wpa_supplicant.conf` с шестнадцатеричным SSID и производным
PBKDF2 WPA2-PSK, без текстового пароля. PSK тоже является ключом доступа:
его нельзя публиковать. Конфигурация упаковывается в ext4 rootfs, который
Thingino читает до запуска Wi-Fi: так избегаем мастера настройки AP.

## 4. Собрать только локальный персональный образ

```sh
cd ~/myipcam/wificam_T23N
PUBLISH=0 THINGINO_FAST=0 sh scripts/build_thingino_wificam_image.sh
```

Сначала чистая сборка; `THINGINO_FAST=1` использовать только после
успешной первоначальной сборки, если сохранён кеш.

Когда есть `local/wifi.env`, итоговые файлы специально уходят в
**gitignored `out/private-sd/`**, не изменяя публичный
`Thingino/thingino-t23-sd.bin`:

```text
out/private-sd/thingino-t23-sd.bin
out/private-sd/thingino-t23-sd.bin.sha256
out/private-sd/IMAGE_INFO.txt
```

Сборщик **запрещает `PUBLISH=1`** при наличии локального Wi-Fi
файла. Это предотвращает случайную отправку домашнего PSK вместе с
бинарником на публичный GitHub. Не отправлять `out/private-sd`,
`out/rootfs-overlay`, `out/thingino-wificam-rootfs-overlay` и
`rootfs.ext2` в Releases/Issues/чаты.

Успешная сборка проверяет MBR/MSPL, rootfs, наличие CGI и Dropbear; это
всё ещё **не означает**, что вебморда/звук/моторы прошли тест на железе.
Не публиковать как готовый релиз до проверки.

## 5. Перезаписать прежнюю SD только после проверки USB-устройства

По скриншоту Windows старый носитель обозначен как
**«Диск 2, съёмный, 29,12 ГБ»** с BOOT (E:) 16 МБ и разделом 64 МБ.
Номера Windows и Linux **не совпадают автоматически**. Не трогать
Windows Диск 0 (D:) и Диск 1 (C:/F:, BitLocker).

В **PowerShell администратора**:

```powershell
usbipd list
# Уточнить текущий BUSID Realtek кардридера в выводе usbipd.
# Подставить РЕАЛЬНЫЙ BUSID:
usbipd bind --busid <BUSID>        # один раз, если ещё не Shared
usbipd attach --wsl --busid <BUSID>
```

В **WSL**:

```sh
lsusb
lsblk -o NAME,PATH,SIZE,MODEL,TRAN,RM,FSTYPE,MOUNTPOINTS
lsblk -dn -o NAME,PATH,SIZE,MODEL,TRAN,RM,TYPE
```

Только когда достоверно идентифицирован **съёмный USB-кардридер**
`TRAN=usb`, `RM=1` и около 29.1 GiB, использовать его
реальный путь `/dev/sdX` (без номера раздела):

```sh
cd ~/myipcam/wificam_T23N
sudo sh scripts/write_thingino_wificam_sd.sh \
    /dev/ПРОВЕРЕННЫЙ_SD_ДИСК \
    "$PWD/out/private-sd/thingino-t23-sd.bin"
```

`/dev/ПРОВЕРЕННЫЙ_SD_ДИСК` — **заполнитель**, не копировать
его как имя устройства! Writer ещё раз проверит `TRAN=usb`, `RM=1`,
размер, MBR, MSPL LBA34, p1/p2, потребует **точную строку подтверждения**,
перепишет старую прошивку новым полным образом от LBA0 и сверит SHA256
полным чтением. Отдельно форматировать разделы Windows **не нужно**.
Оставшиеся 29 ГБ карты пока не расширять: сначала убедиться в загрузке
камеры без SPI/NOR. Физическую запись из ChatGPT GitHub-коннектора
выполнить нельзя: её делает WSL на Acer.

## 6. Подключение после первой загрузки

Полностью обесточить камеру, установить SD, подать питание. Thingino
читает готовый `/etc/wpa_supplicant.conf` и пытается подключиться к
указанной 2.4-ГГц сети. Если пароль/диапазон неверны, соединение может
не появиться; captive portal всё ещё зависит от штатной логики Thingino.
Только аппаратный тест подтвердит готовность.

В Tenda TX12 открыть список DHCP-клиентов и найти новое устройство по
MAC/имени Thingino. **IP определяет DHCP**, не считать старый
`192.168.1.55` гарантированным. После обнаружения закрепить за камерой
DHCP-reservation, не прописывая произвольный статический IP в прошивку.

Открыть с Acer в той же LAN:

```text
PegineLab WIFICAM: http://IP_КАМЕРЫ:8090/
Thingino stock UI: http://IP_КАМЕРЫ/
SSH recovery:       ssh root@IP_КАМЕРЫ
```

Текущий профиль ещё содержит **тестовые** веб-реквизиты
`admin / Wificam12345` и stock SSH `root/root`, если они не были
изменены. **Сменить их после проверки доступа**; не открывать
`:8090`, RTSP и SSH прямо в Интернет. Если CGI API или звук не работает
на первом старте, сохранить SSH и собрать логи, а не выключать Raptor.

## 7. Проверки после прошивки

- SD BootROM действительно грузит SPL/U-Boot при физически отсутствующей
  SPI/NOR, Linux монтирует `/dev/mmcblk0p2`.
- Camera Wi-Fi подключена именно к нужной домашней сети, DHCP выдал IP.
- SSH по 22 доступен после перезагрузки.
- PegineLab `:8090`: HTML+JSON CGI, снимок, lazy MJPEG.
- Hombo3 получает RTSP; при закрытии вебморды RTSP остаётся активен.
- Моторы PTZ, реверс, изображение, микрофон/динамик — проверяются
  физически; не объявлять auto-focus/optical zoom рабочими без привода.

Для восстановления всегда есть [старый `0.1_test` SD-образ](https://github.com/musikfed/wificam_T23N/releases/tag/0.1_test).
