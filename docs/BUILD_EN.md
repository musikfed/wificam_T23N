# Kernel build — Ingenic T23/T23N

## Current result

Linux 3.10.14 for MIPS/Ingenic builds successfully:

```text
Image Name:   Linux-3.10.14__isvp_pike_1.0__
Image Type:   MIPS Linux Kernel Image (lzma compressed)
Data Size:    1739320 Bytes
Load Address: 80010000
Entry Point:  803c7960
```

Resulting image:

```text
~/myipcam/build/kernel/arch/mips/boot/uImage
```

Known-good SHA-256:

```text
7ba1c4b0a3ea28d3a7a89cd14330fe1968a0ac63166b08c2d9e715541432565f
```

## Build

Kernel sources:

```text
~/myipcam/kernel/openipc-linux
```

After configuring the MIPS cross-toolchain and kernel configuration, run the project's build script or the equivalent `make` command.

A successful build ends with:

```text
LD      vmlinux
OBJCOPY arch/mips/boot/vmlinux.bin
LZMA    arch/mips/boot/vmlinux.bin.lzma
UIMAGE  arch/mips/boot/uImage.lzma
Image arch/mips/boot/uImage is ready
```

## Preserve a known-good build

```bash
mkdir -p ~/myipcam/deploy/t23-kernel-known-good
cp -L ~/myipcam/build/kernel/arch/mips/boot/uImage ~/myipcam/deploy/t23-kernel-known-good/
cp ~/myipcam/build/kernel/vmlinux ~/myipcam/deploy/t23-kernel-known-good/
cp ~/myipcam/build/kernel/System.map ~/myipcam/deploy/t23-kernel-known-good/
cp ~/myipcam/build/kernel/.config ~/myipcam/deploy/t23-kernel-known-good/kernel.config
sha256sum ~/myipcam/deploy/t23-kernel-known-good/*
```

## Verify uImage

```bash
mkimage -l ~/myipcam/build/kernel/arch/mips/boot/uImage
```

Do not write this image to SPI/NOR/NAND until UART and a non-destructive SD/RAM boot have been validated.
