# Сборка ядра — Ingenic T23/T23N

## Текущий результат

Успешно собран Linux 3.10.14 для MIPS/Ingenic:

```text
Image Name:   Linux-3.10.14__isvp_pike_1.0__
Image Type:   MIPS Linux Kernel Image (lzma compressed)
Data Size:    1739320 Bytes
Load Address: 80010000
Entry Point:  803c7960
```

Готовый образ:

```text
~/myipcam/build/kernel/arch/mips/boot/uImage
```

SHA-256 успешной сборки:

```text
7ba1c4b0a3ea28d3a7a89cd14330fe1968a0ac63166b08c2d9e715541432565f
```

## Сборка

Исходники ядра находятся в:

```text
~/myipcam/kernel/openipc-linux
```

После настройки toolchain и конфигурации ядра выполняется штатный build-скрипт проекта либо `make` с MIPS cross-compiler.

Успешное завершение должно содержать:

```text
LD      vmlinux
OBJCOPY arch/mips/boot/vmlinux.bin
LZMA    arch/mips/boot/vmlinux.bin.lzma
UIMAGE  arch/mips/boot/uImage.lzma
Image arch/mips/boot/uImage is ready
```

## Сохранение контрольной сборки

```bash
mkdir -p ~/myipcam/deploy/t23-kernel-known-good
cp -L ~/myipcam/build/kernel/arch/mips/boot/uImage ~/myipcam/deploy/t23-kernel-known-good/
cp ~/myipcam/build/kernel/vmlinux ~/myipcam/deploy/t23-kernel-known-good/
cp ~/myipcam/build/kernel/System.map ~/myipcam/deploy/t23-kernel-known-good/
cp ~/myipcam/build/kernel/.config ~/myipcam/deploy/t23-kernel-known-good/kernel.config
sha256sum ~/myipcam/deploy/t23-kernel-known-good/*
```

## Проверка uImage

```bash
mkimage -l ~/myipcam/build/kernel/arch/mips/boot/uImage
```

Не прошивать образ во SPI/NOR/NAND до проверки через UART и безопасной загрузки с SD/RAM.


## Thingino/MMC — текущая проверенная сборка

Для текущего SD/MMC workflow используется зафиксированный upstream Thingino:

```text
Thingino commit: 9925f46f73b9c39ec8d2a65134b18c94e6fdfb97
Camera profile:  galayou_g2_t23n_sc2336_atbm6012bx
Target artifact: Thingino/thingino-t23-sd.bin
```

Web UI PegineLab WIFICAM является обязательной частью итогового образа и не должна исключаться из rootfs/overlay.

Рекомендуемый запуск из корня `wificam_T23N`:

```bash
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
PUBLISH=1 sh scripts/build_thingino_wificam_image.sh
```

### Ошибка Buildroot: PATH contains spaces, TABs, and/or newline

Buildroot отклоняет `PATH`, если в нём присутствуют пробелы, TAB или переносы строк. Типичная ошибка:

```text
Your PATH contains spaces, TABs, and/or newline (\n) characters.
This doesn't work. Fix your PATH environment variable.
```

В этом случае не нужно удалять checkout Thingino или клонировать его заново. Повторите сборку с чистым `PATH`, как в команде выше.

Для диагностики текущего `PATH`:

```bash
printf '%s\n' "$PATH" | tr ':' '\n' | nl -ba
```

Pinned commit и профиль камеры должны быть видны в начале build log до запуска Buildroot.
