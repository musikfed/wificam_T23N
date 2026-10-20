# T23N: восстановление исторически работавшей загрузки с SD

Цель этого этапа — **не строить сразу постоянный SD-root**, а сначала в точности
воспроизвести схему, с которой эта камера раньше запускалась с SD после снятия
SPI/NOR.

Пока этот тест не подтверждён на камере, не создаём p2/p3 и не запускаем
`flash_full_firmware_sd.sh`.

## Что должно получиться

```text
LBA 0            DOS/MBR, signature 55aa
LBA 34..404      raw u-boot-isvp_t23n_msc0_mmc1bit.bin
LBA 2048         p1 BOOT, FAT32, 128 MiB
BOOT:/           autoupdate-full.bin
после p1         неразмеченное место
```

Pinned U-Boot:

```text
file   : u-boot-isvp_t23n_msc0_mmc1bit.bin
size   : 189685 bytes
SHA256 : 4d4d4ff27acce1e5e59577c35ef98a505ae42a0bbb07583380463a81cdbfd6a5
raw    : bs=512 seek=34
```

## 1. Подтянуть репозиторий

```sh
cd ~/myipcam/wificam_T23N
git switch mymarrchWFcam
git pull
git rev-parse --short HEAD
```

## 2. Подключить SD к WSL

Для USB-кардридера в этой установке используем **usbipd**, потому что этот путь
уже фактически давал карту в WSL как `/dev/sde`.

`usbipd` и `wsl.exe` запускаются в **Windows PowerShell**, а не внутри
Ubuntu/WSL. Если в Ubuntu появляется:

```text
Command 'usbipd' not found
```

или:

```text
Command 'wsl' not found
```

не устанавливать одноимённые Ubuntu-пакеты: это не Windows-команды.

В Windows PowerShell:

```powershell
usbipd list
```

Найти USB-кардридер и его текущий `BUSID`. Если он ещё не Shared, в
PowerShell от администратора:

```powershell
usbipd bind --busid BUSID
```

Затем:

```powershell
usbipd attach --wsl --busid BUSID
```

После успешного `usbipd attach --wsl ...` **ничего больше в PowerShell для
этого шага не требуется**. Вернуться в уже открытый Ubuntu/WSL и сразу выполнить:

```sh
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS
```

Это подтверждённый рабочий порядок на текущем хосте:

```text
Windows PowerShell:
  usbipd list
  usbipd bind --busid BUSID      # только если ещё не Shared
  usbipd attach --wsl --busid BUSID

Ubuntu/WSL:
  lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS
```

**Не выполнять `wsl --mount ...` внутри Ubuntu.** Команда `wsl.exe` относится
к Windows; ошибка `Command 'wsl' not found` внутри Ubuntu ничего не монтирует и
не нужна. Не устанавливать `sudo apt install wsl` ради этой операции.

Для этой карты ожидаем около `29.1G`, модель кардридера `SD/MMC/MS PRO`,
`TRAN=usb`, `RM=1`. Имя `/dev/sdX` может меняться после каждого
переподключения, поэтому его всегда определять заново. Системный WSL-диск
выбирать нельзя.

Если после подключения видны старые разделы `BOOT/ROOTFS/MEDIA`, это нормально:
это содержимое предыдущего тестового образа. Скрипт
`prepare_legacy_thingino_sd.sh` всё равно заново создаст один 128 MiB FAT32
BOOT-раздел и оставит остальное место неразмеченным.

Не смешивать одновременно `usbipd attach` и `wsl --mount` для одного и того
же кардридера. Если всё же используется `wsl --mount`, эта команда тоже
выполняется только в Windows PowerShell.

## 3. Проверить U-Boot

```sh
cd ~/myipcam/wificam_T23N
sha256sum out/u-boot-t23n-sd.bin
wc -c out/u-boot-t23n-sd.bin
```

Ожидается:

```text
4d4d4ff27acce1e5e59577c35ef98a505ae42a0bbb07583380463a81cdbfd6a5
189685 bytes
```

Если hash или размер другой — карту не писать.

## 4. Найти настоящий autoupdate-full.bin

```sh
find ~/myipcam -type f -name 'autoupdate-full.bin' -print
```

Если команда ничего не вывела, файла действительно нет.

Upstream `thingino-installers` для T23N обычно делает именно такую операцию:
скачивает **конкретный профиль камеры** вида
`thingino-<camera>_t23n_<sensor>_<wifi>.bin` и переименовывает его в
`autoupdate-full.bin`. Поэтому само переименование допустимо, но только после
точного выбора профиля sensor/Wi-Fi/board. Случайный `thingino-t23n.bin`
использовать нельзя.

Для удобства в этом репозитории есть helper:

```sh
sh scripts/fetch_thingino_autoupdate.sh thingino-ТОЧНЫЙ_ПРОФИЛЬ.bin
```

Он скачивает указанный asset из latest release Thingino и сохраняет его как:

```text
out/autoupdate-full.bin
```

Helper специально **не угадывает профиль**. Имя asset должно быть подтверждено
по железу или по ранее рабочей конфигурации.

Если файла пока нет, можно подготовить только boot geometry без payload:

```sh
sudo sh scripts/prepare_legacy_thingino_sd.sh /dev/sdX
```

Но для воспроизведения прежнего installer boot нужен файл:

```sh
sudo sh scripts/prepare_legacy_thingino_sd.sh /dev/sdX /полный/путь/autoupdate-full.bin
```

## 5. Что делает скрипт

Порядок специально фиксирован:

```text
1. Удаляет старую разметку в начале SD.
2. Создаёт ТОЛЬКО p1:
      start = LBA 2048
      size  = 262144 sectors = 128 MiB
      type  = 0c
      bootable
3. Форматирует p1 в FAT32 с label BOOT.
4. ПОСЛЕ форматирования пишет U-Boot на весь диск:
      dd ... bs=512 seek=34
5. Проверяет:
      MBR = 55aa
      LBA34 magic = MSPL
      полный raw U-Boot SHA256
      p1 start = 2048
      p1 size = 128 MiB
6. Копирует BOOT:/autoupdate-full.bin и проверяет его SHA256.
7. Не создаёт ROOTFS/MEDIA. Остальное место остаётся UNALLOCATED.
```

Ожидаемый финал:

```text
LEGACY THINGINO RECOVERY SD: VERIFIED
MBR signature            : 55aa
Raw MSPL magic           : 4d53504c
Raw U-Boot sector span   : 34..404
Raw U-Boot SHA256        : 4d4d4ff27acce1e5e59577c35ef98a505ae42a0bbb07583380463a81cdbfd6a5
BOOT partition start     : sector 2048
BOOT partition size      : 128 MiB
BOOT filesystem          : FAT32
Remaining card space     : intentionally UNALLOCATED
```

## 6. Ручной эквивалент для проверки другим ИИ

Суть автоматического скрипта равна следующей последовательности:

```sh
sudo sfdisk /dev/sdX <<'EOF'
label: dos
unit: sectors

start=2048, size=262144, type=0c, bootable
EOF

sudo mkfs.vfat -F 32 -n BOOT /dev/sdX1

sudo dd if=out/u-boot-t23n-sd.bin \
  of=/dev/sdX \
  bs=512 \
  seek=34 \
  conv=notrunc,fsync
```

После этого `autoupdate-full.bin` кладётся в корень p1.

Ручные команды приведены только для анализа/сверки. На рабочей карте лучше
использовать `prepare_legacy_thingino_sd.sh`, потому что он дополнительно
проверяет устройство, размер сектора, hash и readback.

## 7. Тест в камере

После успешной проверки:

```sh
sync
```

Затем полностью снять питание камеры, вставить SD и только после этого подать
питание.

**Не добавлять p2/p3 до результата этого теста.**

Если камера ожила, фиксируем этот layout как аппаратно подтверждённый и только
потом расширяем карту под постоянный ROOTFS/MEDIA, не меняя область LBA0..2047.

Если камера всё равно полностью молчит, следующий анализ ограничиваем ранней
цепочкой `BootROM -> SD -> MSPL/SPL`: профиль MSC, boot straps, card detect,
питание SD и T23/T23N boot-ROM requirements. Kernel/rootfs в таком случае пока
не трогаем.

## Важное замечание про autoupdate

В актуальном upstream-коде `sdupdate` присутствуют операции
`sf erase` / `sf write`. Поэтому сам факт наличия
`autoupdate-full.bin` ещё не доказывает постоянную работу без SPI.

Здесь этот файл используется потому, что задача этапа — **точно воспроизвести
исторически работавший сценарий**, а затем по фактическому поведению камеры
отделить раннюю SD-загрузку от механизма установки firmware.
