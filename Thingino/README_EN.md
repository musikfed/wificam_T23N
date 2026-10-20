# Thingino T23N SD + PegineLab WIFICAM

## 0.1_test status

**HARDWARE VERIFIED on 2026-10-21.** The canonical
`Thingino/thingino-t23-sd.bin` was written to SD, passed full readback
SHA256/MBR/MSPL/partition verification, and booted on the target camera.
PegineLab WIFICAM was also confirmed working on the real device.

Pinned SHA256:

```text
f9f50a8595d4fe629ed787483188319000d2780bd3c6dee56fef4de5e754f6be
```


## Canonical image

The current hardware test uses a direct MMC/SD disk image:

```text
Thingino/thingino-t23-sd.bin
```

This is **not** an `autoupdate-full.bin` payload for SPI/NOR. The image is
written to the whole SD card and is intended to boot with the external SPI/NOR
physically absent.

Hardware-verified profile:

```text
galayou_g2_t23n_sc2336_atbm6012bx
SoC    : T23N
sensor : SC2336
Wi-Fi  : ATBM6012BX
```

Why this profile: local shell history shows that this exact Thingino profile was
built previously and its image was copied to
`/mnt/d/Thingino/thingino-t23-sd.bin`.

The 2026-10-21 hardware test confirmed that this profile boots on the target camera.

## Mandatory Web UI

PegineLab WIFICAM is a required part of the canonical image, not an optional
post-install step.

After a successful boot the expected interfaces are:

```text
Thingino Web UI       : http://CAMERA_IP/
PegineLab WIFICAM     : http://CAMERA_IP:8080/
```

WIFICAM provides:

- its own HTML/CSS/JS interface;
- CGI JSON API;
- real snapshot preview through Thingino `prudyntctl`;
- camera start/stop through Thingino `S31prudynt`;
- snapshot and recording controls;
- Wi-Fi status/configuration;
- storage status;
- optional SSH / WireGuard / AmneziaWG controls;
- persistent WIFICAM state under `/opt/wificam`.

The build script **fails and refuses to publish the image** unless WIFICAM is
verified inside the actual `rootfs.ext2`.

## Build and publish

After updating the main project checkout:

```sh
cd ~/myipcam/wificam_T23N
git pull
PUBLISH=1 sh scripts/build_thingino_wificam_image.sh
```

There is **no separate manual Thingino clone prerequisite anymore**. The build
script creates the pinned checkout automatically when it is missing.

The script:

1. looks for a Thingino checkout at `~/myipcam/thingino-firmware`,
   `~/thingino-firmware`, or `~/myipcam/Thingino/thingino-firmware`;
2. if none exists, it **clones**
   `https://github.com/themactep/thingino-firmware.git` with submodules into
   `~/myipcam/thingino-firmware`;
3. it checks out the pinned commit
   `9925f46f73b9c39ec8d2a65134b18c94e6fdfb97` so upstream changes cannot
   silently alter the candidate between tests;
4. builds `galayou_g2_t23n_sc2336_atbm6012bx`;
5. enables MMC0 1-bit boot;
6. sets root to `/dev/mmcblk0p2`, ext4;
7. enables BusyBox httpd for the independent WIFICAM service on TCP 8080;
   The minimal PegineLab admin requires only `CONFIG_HTTPD`,
   `CONFIG_FEATURE_HTTPD_CGI`, `CONFIG_FEATURE_HTTPD_BASIC_AUTH`, and
   `CONFIG_FEATURE_HTTPD_AUTH_MD5`. The minimal HTTP flags are supplied through Buildroot's supported
   `BR2_PACKAGE_BUSYBOX_CONFIG_FRAGMENT_FILES` setting. This matters for the
   pinned Thingino revision because its `BUSYBOX_KCONFIG_FRAGMENT_FILES += ...`
   append is later overwritten by `package/busybox/busybox.mk`. If a FAST
   build still contains a stale BusyBox `.config`, the wrapper runs
   `br-busybox-reconfigure`, verifies the four flags, and regenerates
   `rootfs.ext2`;
8. injects WIFICAM directly through Buildroot's rootfs overlay;
9. if `cleanbuild` did not emit `rootfs.ext2`, explicitly runs the Buildroot `rootfs-ext2` target;
10. verifies WIFICAM in the build target and inside `rootfs.ext2` with `debugfs`;
11. assembles a real SD disk image: DOS/MBR + pinned MMC U-Boot at LBA34 + FAT p1 + ext4 p2;
12. writes it to `Thingino/thingino-t23-sd.bin`;
13. creates SHA256 and `Thingino/IMAGE_INFO.txt`;
14. with `PUBLISH=1`, commits and pushes the canonical artifacts.

If the historical file `/mnt/d/Thingino/thingino-t23-sd.bin` exists, its size
and SHA256 are also recorded in `IMAGE_INFO.txt` for provenance comparison.

## Canonical MMC layout

The current Thingino MMC builder creates:

```text
sector 0        DOS/MBR partition table + 55aa
sector 34       SPL / MSPL
sector 86       U-Boot proper
sector 2048     p1 FAT16 (16 MiB), /uImage
sector 34816    p2 ext4, Thingino rootfs + PegineLab WIFICAM
after image     intentionally unused for the first hardware test
```

U-Boot is expected to load:

```text
mmc 0:1 /uImage
root=/dev/mmcblk0p2
rootfstype=ext4
```

## Write the SD card

Under WSL2, pass the USB card reader from Windows to WSL first. Run
`usbipd` in **Windows PowerShell as Administrator**, not inside Ubuntu/WSL:

```powershell
usbipd list
usbipd bind --busid <BUSID>
usbipd attach --wsl --busid <BUSID>
```

Use only the actual BUSID reported for the intended card reader.

Verified example for the current Acer/Realtek reader:

```text
Windows usbipd list:
BUSID 3-2
VID:PID 0bda:0177
DEVICE Realtek USB 2.0 Card Reader
STATE Shared
```

When the state is already `Shared`, another `bind` is unnecessary. Run only:

```powershell
usbipd attach --wsl --busid 3-2
```

The successful attach for this reader was confirmed inside WSL as:

```text
lsusb:
0bda:0177 Realtek Semiconductor Corp. USB2.0-CRW

lsblk:
sde    /dev/sde   29.1G  SD/MMC/MS PRO  usb  RM=1
└─sde1 /dev/sde1 128M   BOOT  vfat
```

`/dev/sde` is confirmed only for this specific session. After reconnecting,
always verify the size, MODEL, `TRAN=usb`, and `RM=1` again.

After attach, identify the card again inside WSL:

```sh
lsusb
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS
```

The current card should be roughly 29.1 GiB with `TRAN=usb` and `RM=1`.
Never write to WSL Virtual Disk devices.

**Offset rule:** `Thingino/thingino-t23-sd.bin` is a complete disk image.
Always write it from **LBA0 / byte 0**, with no `seek=`. The required boot
offset is already encoded inside the image:

```text
LBA0      MBR
LBA34     SPL/MSPL
LBA86     U-Boot proper
LBA2048   p1 FAT16 /uImage
LBA34816  p2 ext4 rootfs
```

If the card appears as `/dev/sde`:

```sh
sudo sh scripts/write_thingino_wificam_sd.sh /dev/sde
```

Confirmation string:

```text
THINGINO-WIFICAM:/dev/sde
```

Before writing, the writer verifies the SHA256 sidecar, MBR `55aa`, MSPL at
LBA34, and p1/p2 starts in the source image. It then writes the whole image
from LBA0 and verifies full-image SHA readback, `55aa`, LBA34 MSPL, p1 at
LBA2048 and p2 at LBA34816. Do not use manual `dd ... seek=34` with the
finished `thingino-t23-sd.bin`; that would shift the whole disk image and
break the MBR.

## First hardware test

After a successful write:

```sh
sync
```

Remove camera power completely, insert the SD card, then apply power.

Acceptance criteria:

```text
1. The board shows Linux boot activity.
2. Thingino/Wi-Fi comes up.
3. The normal Thingino Web UI is reachable.
4. PegineLab WIFICAM MUST be reachable on :8080.
5. WIFICAM status API responds.
6. Snapshot preview works once Prudynt is running.
```

Only after this succeeds should the unused capacity of the 32-GB card be
expanded/partitioned for persistent MEDIA storage. The proven low-level
boot/SPL/U-Boot area must remain unchanged.

## Legacy recovery

The one-partition FAT32 + LBA34 + `autoupdate-full.bin` path is retained as a
separate diagnostic experiment:

```text
scripts/prepare_legacy_thingino_sd.sh
scripts/verify_legacy_thingino_sd.sh
```

Do not mix it with the canonical direct-MMC image. They are separate boot tests.
