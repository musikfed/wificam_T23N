# Полная запись SD для T23/T23N без SPI/NOR

Эта инструкция относится к камере, у которой внешняя SPI/NOR flash **физически снята**.
SD содержит всю загрузочную цепочку.

## 1. Обновить ветку

```sh
cd ~/myipcam/wificam_T23N
git switch mymarrchWFcam
git pull
```

## 2. Установить host tools

```sh
sudo apt install -y git make gcc python3 curl squashfs-tools dosfstools fdisk e2fsprogs lzop
```

## 3. Пересобрать kernel для SD root

```sh
sh scripts/build_kernel.sh
```

Скрипт требует built-in:

```text
CONFIG_MMC=y
CONFIG_MMC_BLOCK=y
CONFIG_JZMMC_V12=y
CONFIG_JZMMC_V12_MMC0=y
CONFIG_EXT4_FS=y
CONFIG_MSDOS_PARTITION=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
```

Это обязательно: kernel не может загрузить MMC/ext4 module из rootfs, пока сам rootfs ещё не смонтирован.

## 4. Собрать специальный SD SPL/U-Boot

```sh
sh scripts/build_sd_bootloader.sh
```

Результат:

```text
out/u-boot-t23n-sd.bin
```

Это MMC/SPL build, а не SPI/SFC U-Boot.

## 5. Найти SD

```sh
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS
```

После каждого detach/re-attach имя `/dev/sdX` проверяется заново.

## 6. Записать всё

```sh
sudo sh scripts/flash_full_firmware_sd.sh /dev/ВАША_SD
```

Скрипт потребует строку вида:

```text
AUTONOMOUS-SD:/dev/sdX
```

После подтверждения вся карта переразмечается.

## Raw boot map

```text
sector 0       MBR
sector 34      SPL/U-Boot image start (17 KiB)
sector 86      U-Boot proper
sector 514     U-Boot environment
sector 0x1800  uImage (3 MiB)
                raw kernel slot = 0x3000 sectors = 6 MiB
16 MiB         p1 BOOT FAT32, 128 MiB
144 MiB        p2 ROOTFS ext4
...            p3 MEDIA ext4, fixed 20 GiB near end
```

U-Boot загружает kernel напрямую из raw SD:

```text
mmc read 0x80600000 0x1800 0x3000
bootm 0x80600000
```

Linux root:

```text
/dev/mmcblk0p2
rootfstype=ext4
```

## 7. Первый запуск

После успешного завершения flash script:

```sh
sync
```

Отсоединить карту от WSL, вставить её в обесточенную камеру, подключить UART 115200
и только потом подать питание. Нужен полный лог от первой строки.

SPI/NOR для этого сценария не требуется.
