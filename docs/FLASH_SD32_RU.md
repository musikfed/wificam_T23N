# Полная запись SD для T23/T23N без SPI/NOR

Эта инструкция относится к камере, у которой внешняя SPI/NOR flash
**физически снята**. SD содержит всю постоянную загрузочную цепочку.

## 1. Обновить ветку

```sh
cd ~/myipcam/wificam_T23N
git switch mymarrchWFcam
git pull
```

## 2. Собрать/получить artifacts

```sh
sh scripts/build_all.sh
```

Для bootloader используется точный upstream
`u-boot-isvp_t23n_msc0_mmc1bit.bin`, release
`uboot-xb1-2025-09-11`, SHA-256
`4d4d4ff27acce1e5e59577c35ef98a505ae42a0bbb07583380463a81cdbfd6a5`.

## 3. Найти SD

```sh
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS
```

После каждого detach/re-attach имя `/dev/sdX` проверяется заново.

## 4. Записать всё

```sh
sudo sh scripts/flash_full_firmware_sd.sh /dev/ВАША_SD
```

Скрипт потребует подтверждение вида:

```text
AUTONOMOUS-SD:/dev/sdX
```

## Карта загрузки

The first 36 bytes of sector 0 are the Ingenic MMC descriptor; the DOS
partition table remains at byte 446 in the same sector.

```text
sector 0       INGE descriptor + MBR partition table
sector 34      SPL/U-Boot image start
sector 86      U-Boot proper
sector 546     U-Boot environment (0x44400), 32 KiB
sector 0x1800  резервная raw-копия uImage
16 MiB         p1 BOOT FAT32, активный /uImage
144 MiB        p2 ROOTFS ext4
...            p3 MEDIA ext4, fixed 20 GiB
```

Upstream U-Boot загружает активный kernel с FAT32:

```text
mmc rescan
fatload mmc 0:1 ${baseaddr} uImage
bootm ${baseaddr}
```

Linux root:

```text
/dev/mmcblk0p2
rootfstype=ext4
```

## 5. Первый запуск

После `SD FIRMWARE VERIFY: OK`:

```sh
sync
```

Полностью обесточить камеру, вынуть SD из кардридера, вставить SD в камеру и
только затем подать питание. UART для записи и обязательной проверки карты не
нужен.

Если плата не начинает загрузку даже с точно проверенным upstream MMC U-Boot,
дальше проверяется ранний аппаратный путь BootROM → SD: питание слота,
card-detect/strap и разводка платы. SPI/NOR для этого сценария не используется.
