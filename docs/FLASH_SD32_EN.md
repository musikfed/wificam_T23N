# Writing the 32 GB SD card safely

The provided Windows screenshot identifies the physical card as **Disk 2**, removable, **29.12 GB**, RAW. This does **not** determine its Linux path.

Find it first:

```sh
lsblk -o NAME,PATH,SIZE,MODEL,TRAN,RM,FSTYPE,MOUNTPOINTS
```

Then run:

```sh
sudo sh scripts/flash_sd_32gb_safe.sh /dev/YOUR_SD \
  ~/myipcam/build/kernel/arch/mips/boot/uImage
```

With a complete rootfs:

```sh
sudo sh scripts/flash_sd_32gb_safe.sh /dev/YOUR_SD \
  ~/myipcam/build/kernel/arch/mips/boot/uImage \
  out/wificam-rootfs.tar.gz
```

The wrapper displays the disk again and requires typing the exact Linux device path before erasing it.

Layout: 128 MiB BOOT + remaining ROOTFS + fixed 20 GiB MEDIA.
