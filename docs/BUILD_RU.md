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
