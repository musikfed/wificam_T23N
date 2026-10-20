# Thingino T23N SD + PegineLab WIFICAM

## Canonical image

The current hardware test uses a direct MMC/SD disk image:

```text
Thingino/thingino-t23-sd.bin
```

This is **not** an `autoupdate-full.bin` payload for SPI/NOR. The image is
written to the whole SD card and is intended to boot with the external SPI/NOR
physically absent.

Current candidate profile:

```text
galayou_g2_t23n_sc2336_atbm6012bx
SoC    : T23N
sensor : SC2336
Wi-Fi  : ATBM6012BX
```

Why this profile: local shell history shows that this exact Thingino profile was
built previously and its image was copied to
`/mnt/d/Thingino/thingino-t23-sd.bin`.

That is strong provenance evidence, but it is **not yet proof** that
`GV-T23-PTZ-MAIN-V2.0` is actually SC2336 + ATBM6012BX. Real hardware boot is
the final confirmation.

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

After one update of the main project checkout:

```sh
cd ~/myipcam/wificam_T23N
PUBLISH=1 sh scripts/build_thingino_wificam_image.sh
```

The script:

1. uses the Thingino checkout at `~/myipcam/thingino-firmware` or
   `~/thingino-firmware`;
2. builds `galayou_g2_t23n_sc2336_atbm6012bx`;
3. enables MMC0 1-bit boot;
4. sets root to `/dev/mmcblk0p2`, ext4;
5. enables BusyBox httpd for the independent WIFICAM service on TCP 8080;
6. injects WIFICAM directly through Buildroot's rootfs overlay;
7. verifies WIFICAM in the build target and inside `rootfs.ext2` with
   `debugfs`;
8. writes the canonical artifact to `Thingino/thingino-t23-sd.bin`;
9. creates SHA256 and `Thingino/IMAGE_INFO.txt`;
10. with `PUBLISH=1`, commits and pushes the canonical artifacts.

If the historical file `/mnt/d/Thingino/thingino-t23-sd.bin` exists, its size
and SHA256 are also recorded in `IMAGE_INFO.txt` for provenance comparison.

## Canonical MMC layout

The current Thingino MMC builder creates:

```text
byte 0..35      INGE descriptor
sector 0        DOS/MBR partition table + 55aa
sector 34       SPL / MSPL
sector 86       U-Boot proper
sector 2048     p1 FAT32, /uImage
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

Always identify the SD card again immediately before a destructive write:

```sh
lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS
```

The current reader/card should look roughly like:

```text
29.1G  SD/MMC/MS PRO  usb  RM=1
```

Never write to the WSL system disk `/dev/sdd`.

If the card is still `/dev/sde`:

```sh
sudo sh scripts/write_thingino_wificam_sd.sh /dev/sde
```

Confirmation string:

```text
THINGINO-WIFICAM:/dev/sde
```

The writer verifies full-image SHA readback, `INGE`, `55aa`, LBA34
`MSPL`, p1 at LBA2048 and p2 at LBA34816.

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
