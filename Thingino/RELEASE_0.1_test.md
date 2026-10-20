# PegineLab WIFICAM T23 SD — 0.1_test

**Status:** hardware verified / аппаратно подтверждено  
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
- PegineLab WIFICAM включена в rootfs; runtime-проверка `http://CAMERA_IP:8080/` ещё требуется.

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
- PegineLab WIFICAM is embedded in rootfs; runtime verification at `http://CAMERA_IP:8080/` is still required.

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

PegineLab WIFICAM : http://CAMERA_IP:8080/
```

Seeing `https://CAMERA_IP/login.html` with Thingino branding is expected and
does not mean PegineLab was replaced. WIFICAM must be tested separately on
HTTP port 8080.

First WIFICAM boot uses `ALLOW_UNAUTHENTICATED_WEB=1`; once a password is
configured, the default WIFICAM username is `admin`.
