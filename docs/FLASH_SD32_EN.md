# Full SD image for T23/T23N with no SPI/NOR

This guide is for hardware where the external SPI/NOR flash is **physically
absent**. The SD card contains the complete persistent boot chain.

## Update and build

```sh
cd ~/myipcam/wificam_T23N
git switch mymarrchWFcam
git pull
sh scripts/build_all.sh
```

The bootloader is the exact upstream
`u-boot-isvp_t23n_msc0_mmc1bit.bin` from release
`uboot-xb1-2025-09-11`, SHA-256
`4d4d4ff27acce1e5e59577c35ef98a505ae42a0bbb07583380463a81cdbfd6a5`.

## Identify and write the SD card

```sh
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS
sudo sh scripts/flash_full_firmware_sd.sh /dev/YOUR_SD
```

Re-check the Linux device name after every detach/re-attach.

The resulting layout is:

The first 36 bytes of sector 0 contain the Ingenic MMC descriptor; the DOS
partition table remains at byte 446 of the same sector.

```text
sector 0       INGE descriptor + MBR partition table
sector 34      SPL/U-Boot image start
sector 86      U-Boot proper
sector 546     U-Boot environment (0x44400), 32 KiB
sector 0x1800  redundant raw uImage copy
16 MiB         p1 BOOT FAT32, active /uImage
144 MiB        p2 ROOTFS ext4
...            p3 MEDIA ext4, fixed 20 GiB
```

Upstream U-Boot loads the active kernel from FAT32:

```text
mmc rescan
fatload mmc 0:1 ${baseaddr} uImage
bootm ${baseaddr}
```

Linux mounts `/dev/mmcblk0p2` as the ext4 root filesystem.

After `SD FIRMWARE VERIFY: OK`, run `sync`, remove the card from the reader,
insert it into the fully powered-off camera, then apply power. UART is not
required for writing or mandatory SD verification.

If the board still does not begin booting with the verified upstream MMC
U-Boot, investigate the early BootROM → SD hardware path: slot power,
card-detect/strap state and board routing.
