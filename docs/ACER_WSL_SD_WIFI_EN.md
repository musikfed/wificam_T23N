# Acer WSL → personalized T23N MMC SD, local-only Wi-Fi

**Hardware constraint:** SPI/NOR IC has been physically removed. T23N must
boot **directly from SD**: MBR LBA0, SPL/MSPL LBA34, U-Boot proper LBA86,
reserved U-Boot env LBA546, FAT16 BOOT p1 LBA2048 with /uImage,
ext4 rootfs p2 LBA34816 (`/dev/mmcblk0p2`). The whole assembled
`thingino-t23-sd.bin` is written starting **at LBA0 without any seek=34**.
Do not change the tested SD bootloader or partition offsets.

**Where:** build in Ubuntu 24.04 WSL on Acer Swift 3 (WSL distribution
stored on Windows D:). Hombo3 backend runs natively on Windows 11.
Cannot operate the user's WSL session or SD card from GitHub API.

## Safe WSL inventory and restore

In Windows PowerShell check `wsl -l -v`, `usbipd list`, `Get-Disk`.
In WSL, do not delete any old camera projects without examining
uncommitted changes, backups, and old images.

```sh
mkdir -p ~/myipcam
if [ ! -e ~/myipcam/wificam_T23N ]; then
  git clone --branch mymarrchWFcam \
    https://github.com/musikfed/wificam_T23N.git ~/myipcam/wificam_T23N
fi
cd ~/myipcam/wificam_T23N
sh scripts/wsl_restore_camera.sh
sh scripts/wsl_camera_inventory.sh
```

These utilities never delete old directories and `restore` only performs
a clean fast-forward update if the Git remote is the expected repository.
Missing Thingino source will be cloned and pinned automatically by the
build wrapper (`9925f46f73b9c39ec8d2a65134b18c94e6fdfb97`).

## Local Wi-Fi credentials, NEVER committed

Use a 2.4-GHz WPA2-Personal/AES network (not 5-GHz-only/WPA3-only):

```sh
cp local/wifi.env.example local/wifi.env
chmod 600 local/wifi.env
nano local/wifi.env
```

Edit the two quoted values to real SSID/password **on Acer only**:

```ini
WIFI_SSID="YOUR_PRIVATE_2GHZ_SSID"
WIFI_PASSWORD="YOUR_PRIVATE_WPA2_PASSPHRASE"
```

Values are JSON-quoted literals, not a sourced shell script. The
generator requires an SSID of 1–32 UTF-8 bytes and a WPA2 passphrase
of 8–63 printable ASCII bytes. Do not share real SSID/passphrase in a
public issue/chat. `local/wifi.env` is Git-ignored, unlike the harmless
`local/wifi.env.example`.

`scripts/prepare_wifi_overlay.py` generates a private
`/etc/wpa_supplicant.conf` in the rootfs overlay, encoding SSID in hex
and deriving a WPA2 PBKDF2-HMAC-SHA1 PSK. **The derived PSK is still a
network secret.** Since pinned Thingino `S38wpa_supplicant` reads this
file at boot to choose client vs portal mode, preprovisioning avoids
manually selecting the camera's AP mode when the credentials work.

## Local-only build and flashing

```sh
PUBLISH=0 THINGINO_FAST=0 sh scripts/build_thingino_wificam_image.sh
```

With local Wi-Fi enabled the output goes to **ignored**
`out/private-sd/thingino-t23-sd.bin` plus `.sha256` and
`IMAGE_INFO.txt`, NOT the versioned
`Thingino/thingino-t23-sd.bin`. The wrapper **refuses PUBLISH=1**
when `local/wifi.env` is present. Never publish the resulting binary,
`rootfs.ext2`, `out/` or the WPA config.

Before writing, identify the actual USB removable SD reader by
**live** `usbipd list` in Windows and `lsusb`/`lsblk` in WSL.
The prior Windows screenshot identified **Disk 2 / 29.12 GiB** but Linux
device names are not predictable; never select `/dev/sdX` by memory.
Do not touch Windows C:/D:/F: or the WSL virtual disk.

The existing writer accepts the personalized image as its **second
argument** and verifies removable USB device, SHA, MSPL magic, MBR,
p1/p2 geometry and full readback. Once the USB target is independently
identified, use:

```sh
sudo sh scripts/write_thingino_wificam_sd.sh /dev/VERIFIED_SD_DISK \
    "$PWD/out/private-sd/thingino-t23-sd.bin"
```

`/dev/VERIFIED_SD_DISK` is intentionally a **placeholder**.
The old firmware is overwritten by the full image from LBA0; separate
Windows formatting/wiping is unnecessary. Leave unallocated remaining
space untouched until hardware boot succeeds.

## Find camera after power cycle

Insert card, fully power off/on the T23N and inspect **Tenda TX12
DHCP leases** for the new camera IP. The old `192.168.1.55` is not
guaranteed. Reserve its DHCP address after it is found. From the
same trusted LAN use:

```text
PegineLab UI: http://CAMERA_IP:8090/
Thingino UI:  http://CAMERA_IP/
Recovery:    ssh root@CAMERA_IP
```

The current dev test image still contains known LAN-only credentials
`admin / Wificam12345` for PegineLab and stock `root/root` for SSH
unless changed: replace before regular operation. Never open these
ports directly to WAN.

**Acceptance is physical:** prove MMC boot with missing SPI chip,
DHCP/Wi-Fi, SSH after reboot, executable CGI JSON, lazy MJPEG/snapshot,
Hombo3 RTSP simultaneously, microphone, speaker and PTZ. A passing
GitHub Actions syntax/unit check is not an actual device test. Preserve
the verified [`0.1_test` recovery release](https://github.com/musikfed/wificam_T23N/releases/tag/0.1_test).
