# Full SD image for T23/T23N with no SPI/NOR

This guide is for hardware where the external SPI/NOR flash is **physically absent**.
The SD card contains the complete boot chain.

## Build the deployable kernel

```sh
cd ~/myipcam/wificam_T23N
git switch mymarrchWFcam
git pull
sh scripts/build_kernel.sh
```

The script requires MMC, the T23 MMC host controller and EXT4 to be built into the
kernel (`=y`), because modules cannot be loaded before the SD root filesystem is
mounted.

## Build the T23N SD SPL/U-Boot

```sh
sh scripts/build_sd_bootloader.sh
```

Result:

```text
out/u-boot-t23n-sd.bin
```

This is a dedicated MMC/SPL build, not a SPI/SFC U-Boot image.

## Identify and write the SD card

```sh
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS
sudo sh scripts/flash_full_firmware_sd.sh /dev/YOUR_SD
```

Re-check the Linux device name after every detach/re-attach.

The writer rebuilds the whole card and uses this raw map:

```text
sector 0       MBR
sector 34      SPL/U-Boot image start (17 KiB)
sector 86      U-Boot proper
sector 514     U-Boot environment
sector 0x1800  uImage (3 MiB), 6 MiB raw slot
16 MiB         p1 BOOT FAT32, 128 MiB
144 MiB        p2 ROOTFS ext4
...            p3 MEDIA ext4, fixed 20 GiB
```

U-Boot reads the kernel with:

```text
mmc read 0x80600000 0x1800 0x3000
bootm 0x80600000
```

Linux mounts `/dev/mmcblk0p2` as the ext4 root filesystem.

After writing, insert the SD into the powered-off camera, attach a 115200 UART,
then power the board and capture the log from the first line. No SPI/NOR boot
storage is required by this layout.
