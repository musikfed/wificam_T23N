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


## Thingino/MMC — current validated build path

The current SD/MMC workflow uses a pinned upstream Thingino revision:

```text
Thingino commit: 9925f46f73b9c39ec8d2a65134b18c94e6fdfb97
Camera profile:  galayou_g2_t23n_sc2336_atbm6012bx
Target artifact: Thingino/thingino-t23-sd.bin
```

The PegineLab WIFICAM Web UI is a mandatory part of the final image and must not be omitted from the rootfs/overlay.

Recommended invocation from the `wificam_T23N` repository root:

```bash
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
PUBLISH=1 sh scripts/build_thingino_wificam_image.sh
```

### Buildroot error: PATH contains spaces, TABs, and/or newline

Buildroot rejects `PATH` values containing spaces, TABs, or newline characters. A typical failure is:

```text
Your PATH contains spaces, TABs, and/or newline (\n) characters.
This doesn't work. Fix your PATH environment variable.
```

Do not delete or reclone the Thingino checkout for this error. Re-run the build with the clean `PATH` shown above.

To inspect the current `PATH`:

```bash
printf '%s\n' "$PATH" | tr ':' '\n' | nl -ba
```

The pinned commit and camera profile should be visible near the start of the build log before Buildroot starts.
