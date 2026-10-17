# Запись 32-ГБ SD — безопасный сценарий

По предоставленному скриншоту Windows карта отображается как **Диск 2**, съёмное устройство, **29.12 ГБ**, RAW. Это подтверждает физическую карту, но **не определяет Linux-путь**: в Linux она может оказаться `/dev/sdb`, `/dev/sdc`, `/dev/mmcblk0` и т. п.

## 1. Переключиться на ветку

```sh
cd ~/myipcam/wificam_T23N
git fetch origin
git switch mymarrchWFcam
git pull
```

## 2. Найти SD в Linux

```sh
lsblk -o NAME,PATH,SIZE,MODEL,TRAN,RM,FSTYPE,MOUNTPOINTS
```

Ищем съёмный диск примерно 29–30 GiB. Не выбираем системный диск.

## 3. Проверить kernel

```sh
ls -lh ~/myipcam/build/kernel/arch/mips/boot/uImage
```

## 4. Форматирование + kernel + PegineLab branding

```sh
sudo sh scripts/flash_sd_32gb_safe.sh /dev/ВАША_SD \
  ~/myipcam/build/kernel/arch/mips/boot/uImage
```

Скрипт повторно показывает устройство и требует вручную набрать его точный путь.

Разметка:

| Раздел | Размер | FS |
|---|---:|---|
| BOOT | 128 MiB | FAT32 |
| ROOTFS | всё оставшееся | ext4 |
| MEDIA | 20 GiB | ext4 |

На BOOT попадают `uImage`, PegineLab logo и boot-jingle.

## 5. С полным rootfs

```sh
sudo sh scripts/flash_sd_32gb_safe.sh /dev/ВАША_SD \
  ~/myipcam/build/kernel/arch/mips/boot/uImage \
  out/wificam-rootfs.tar.gz
```

Не стирать штатную SPI/NOR/NAND камеры до успешного SD/RAM boot.
