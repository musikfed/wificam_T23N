# PegineLab branding and boot splash

This feature lives in the experimental `mymarrchWFcam` branch.

## Included

- PegineLab logo in the Web UI;
- favicon/avatar;
- PegineLab documentation banner;
- original ~7-second 8-bit/chiptune boot jingle;
- early `S05peginelab-boot` init script;
- logo and jingle copies on the SD BOOT partition.

## Design

Branding must **not delay camera boot**. The init script starts splash/audio in the background and returns immediately.

The image is displayed only when `/dev/fb0` exists and `fbv` or `fbi` is installed.

Audio is played only when `aplay` or `tinyplay` is available.

Missing framebuffer/audio support is treated as a no-op.

## Settings

In `/etc/wificam/wificam.conf`:

```text
BOOT_SPLASH=1
BOOT_SOUND=1
BOOT_BRANDING_SECONDS=7
```

Disable sound with:

```text
BOOT_SOUND=0
```

## Size

The jingle is mono 8-bit PCM WAV at 11025 Hz, about 77 KiB, intentionally small for embedded hardware.

Generator source: `tools/generate_boot_jingle.py`.
