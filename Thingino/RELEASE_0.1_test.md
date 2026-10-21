# PegineLab WIFICAM T23 SD — 0.1_test

**Status:** SD boot hardware verified; WIFICAM :8090 runtime check pending / SD boot аппаратно подтверждён; проверка WIFICAM :8090 ожидается  
**Date:** 2026-10-21  
**Branch:** `mymarrchWFcam`

## RU

Первый аппаратно подтверждённый тестовый релиз SD-прошивки для T23N.

Подтверждено на реальной камере:
- загрузка напрямую с SD;
- корректная разметка MBR;
- SPL/MSPL на LBA34;
- U-Boot proper на LBA86;
- FAT16 boot partition с `/uImage`;
- ext4 rootfs на `/dev/mmcblk0p2`;
- PegineLab WIFICAM включена в rootfs; runtime-проверка `http://CAMERA_IP:8090/` ещё требуется.

Файл:
`Thingino/thingino-t23-sd.bin`

Размер:
`84934656 bytes`

SHA256:
`f9f50a8595d4fe629ed787483188319000d2780bd3c6dee56fef4de5e754f6be`

Запись выполняется как полный disk image с LBA0. **Не использовать `seek=34`** для готового `.bin`.

Рекомендуемая команда:
```sh
sudo sh scripts/write_thingino_wificam_sd.sh /dev/sdX
```

## EN

First hardware-verified test release of the direct-SD T23N firmware.

Verified on the target camera:
- direct SD boot;
- valid DOS/MBR layout;
- SPL/MSPL at LBA34;
- U-Boot proper at LBA86;
- FAT16 boot partition with `/uImage`;
- ext4 rootfs at `/dev/mmcblk0p2`;
- PegineLab WIFICAM is embedded in rootfs; runtime verification at `http://CAMERA_IP:8090/` is still required.

Image:
`Thingino/thingino-t23-sd.bin`

Size:
`84934656 bytes`

SHA256:
`f9f50a8595d4fe629ed787483188319000d2780bd3c6dee56fef4de5e754f6be`

Write it as a complete disk image from LBA0. **Do not use `seek=34`** with the finished image.


## Web UI clarification / Уточнение Web UI

The firmware exposes two separate interfaces / В прошивке две отдельные веб-службы:

```text
Thingino stock UI : http://CAMERA_IP/ or https://CAMERA_IP/
login/password    : root / root

PegineLab WIFICAM : http://CAMERA_IP:8090/
```

Seeing `https://CAMERA_IP/login.html` with Thingino branding is expected and
does not mean PegineLab was replaced. WIFICAM must be tested separately on
HTTP port 8090.

First WIFICAM boot uses `ALLOW_UNAUTHENTICATED_WEB=1`; once a password is
configured, the default WIFICAM username is `admin`.


## 8080 conflict / конфликт 8080

Hardware testing showed that Thingino already owns TCP 8080 for its camera/API
stack. PegineLab WIFICAM is therefore assigned TCP **8090**. This is a
userspace-only change and does not require rebuilding the kernel.


## Known issue in the first hardware-booted image / известная ошибка первого образа

The image SHA256 `f9f50a8595d4fe629ed787483188319000d2780bd3c6dee56fef4de5e754f6be`
is confirmed to boot from SD, but its baked WIFICAM runtime is older than the
current source. It contains the original 8080/bootstrap-httpd behavior.

Current source has already fixed the web runtime:
- PegineLab moved to TCP 8090;
- BusyBox httpd is isolated from Thingino `/etc/httpd.conf`;
- first boot exposes only the admin password claim page;
- BusyBox-incompatible `od -A/-N` use was removed.

Until a refreshed image is assembled, the old card can be recovered over SSH
by creating the PegineLab `admin` password and restarting the web services as
documented in `docs/FIRST_BOOT_SSH_RU.md`.

These are userspace/rootfs changes; a Linux kernel rebuild is not required.


## PegineLab test login / тестовый вход

```text
URL:      http://CAMERA_IP:8090/
login:    admin
password: Wificam12345
```

These credentials are intentionally public for the LAN-only `0.1_test`
hardware bring-up. The running T23N image showed a persistent 401 when using
the generated BusyBox MD5-crypt entry, so current source uses the BusyBox
plaintext httpd.conf format for deterministic test access. Change the password
from PegineLab **System** after login. Production builds disable test
auto-provision and use first-boot claim.
