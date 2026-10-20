# Thingino T23N cleanbuild — 2026-10-20

## Result

The Thingino/Buildroot compile itself reached a successful firmware packaging
stage. The outer PegineLab wrapper then failed because it required
`images/rootfs.ext2`, while the pinned Thingino top-level build emitted only
`rootfs.squashfs` for its normal SPI image.

Pinned Thingino: `9925f46f73b9c39ec8d2a65134b18c94e6fdfb97`  
Camera: `galayou_g2_t23n_sc2336_atbm6012bx`  
Build duration: `1:16:12 (4572s)`  
Reported disk writes: `16.3G`

## Successfully produced

- U-Boot build completed and `u-boot-with-tpl-lzma.bin` was installed.
- `uImage` was produced.
- `rootfs.squashfs` was produced; the log reports about 5.00 MiB compressed
  and about 17.3 MiB uncompressed.
- Thingino packaged
  `thingino-galayou_g2_t23n_sc2336_atbm6012bx.bin`.

## Important correction: that 8 MiB .bin is SPI/SFC, not SD

The packaging commands create an 8 MiB erased slab and place the bootloader,
kernel, squashfs rootfs and JFFS2 data at fixed offsets. The generated U-Boot
environment contains:

```text
mtdparts=jz_sfc:320k(boot),64k(env),64k(backup),1600k(kernel),5184k(rootfs),960k(data),8192k@0(all)
```

Therefore this file is the normal SFC/SPI flash image. Renaming or copying it
to `Thingino/thingino-t23-sd.bin` would be wrong and unsafe.

## Fatal error

The final fatal line is:

```text
ERROR: rootfs.ext2 missing: .../images/rootfs.ext2
```

This is not a kernel/compiler failure. The project fragment already enabled:

```text
BR2_TARGET_ROOTFS_EXT2=y
BR2_TARGET_ROOTFS_EXT2_4=y
BR2_TARGET_ROOTFS_EXT2_SIZE="64M"
```

However the pinned Thingino top-level rootfs path explicitly invokes
Buildroot's `rootfs-squashfs` target for the normal firmware pack. Enabling
EXT2/EXT4 alone therefore did not cause `rootfs.ext2` to be emitted.

## Fix — DeepSeek option 1, implemented correctly

The wrapper explicitly runs:

```sh
make CAMERA=galayou_g2_t23n_sc2336_atbm6012bx rootfs-ext2
```

when `rootfs.ext2` is missing. With `BR2_TARGET_ROOTFS_EXT2_4=y`, the
historical Buildroot filename remains `rootfs.ext2`, but its filesystem is
ext4.

The size stays 64 MiB, not 8 MiB. The log already shows roughly 17.3 MiB of
uncompressed rootfs content, so an 8 MiB ext filesystem is not a sensible
target. Modern ext4 incompat features `64bit`, `metadata_csum` and
`orphan_file` are disabled for Linux 3.10 compatibility.

## Non-fatal messages

The host e2fsprogs documentation phase reports missing `texi2dvi` and missing
`.info` files with `Error 127 (ignored)` / `Error 1 (ignored)`. They are
explicitly ignored by that package's make rules and did not stop the build.

Other `make ... -j1 forced` and `libtool --finish` messages are warnings,
not the cause of the final failure.

## DeepSeek answer assessment

Correct: the compile had reached the end, squashfs/rootfs and the 8 MiB
Thingino firmware image existed, and the fatal wrapper error was the missing
`rootfs.ext2`.

Incomplete/incorrect:
- simply adding EXT2 symbols was not enough; they were already present;
- `8M` is too small for this rootfs and was not adopted;
- removing the ext2 check would have allowed the SPI image to be mislabeled as
  a direct SD image;
- creating an empty `rootfs.ext2` would be unsafe and is explicitly rejected.

The corrected pipeline produces/validates ext4 p2 and assembles a separate
direct SD disk image using the pinned MMC SPL/U-Boot at LBA34.
