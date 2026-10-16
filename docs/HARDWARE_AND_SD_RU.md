# Совместимость платы и безопасная проверка

## Для какой платы подходит

Сборка предназначена для камер на **Ingenic T23/T23N** с MIPS/XBurst и Linux 3.10.x.

Совместимость конкретной платы окончательно подтверждается только загрузкой через UART/U-Boot и проверкой RAM, flash, Wi-Fi и GPIO. Определение сенсора не является ручным этапом нашей Web UI: драйверы/штатный camera userspace ОС должны подхватить камеру при загрузке.

## Перед снятием или отключением SPI-flash

Сначала использовать обратимую загрузку через UART/SD.

1. Снять полный дамп штатной flash.
2. Сохранить копии и SHA-256.
3. Сохранить маркировку flash и напряжение.
4. Сохранить U-Boot `printenv` и boot log.
5. Не стирать штатную flash до успешной SD/RAM загрузки.

## U-Boot

```text
version
printenv
bdinfo
mmc list
part list mmc 0
help fatload
help ext4load
help bootm
```

## Актуальная разметка SD

| Раздел | Размер | FS | Назначение |
|---|---:|---|---|
| p1 BOOT | 128 MiB | FAT32 | `uImage`, boot files |
| p2 ROOTFS | всё оставшееся место | ext4 | Linux, приложения, настройки, VPN, SSH, логи |
| p3 MEDIA | 20 GiB | ext4 | видео, фото, события камеры |

`scripts/prepare_sd.sh` вычисляет размер ROOTFS автоматически: карта минус BOOT, 20 GiB MEDIA и небольшой технический запас.

MEDIA:

```text
/mnt/media/
├── recordings/
├── snapshots/
└── events/
```

Настройки Wi-Fi, web auth, VPN и marker-файлы сервисов находятся в `/data` внутри большого ROOTFS.

## Первый запуск

Первый тест — загрузить `uImage` с SD в RAM и выполнить `bootm`, не изменяя штатную flash.
