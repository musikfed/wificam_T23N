# Web UI and API — English

This repository now contains a minimal working embedded web stack, not only a mockup.

## Included

```text
web/index.html            camera menu
web/styles.css            responsive UI
web/app.js                browser/API logic
web/cgi-bin/api           BusyBox CGI JSON API

rootfs/etc/init.d/S90wificam
rootfs/etc/wificam/wificam.conf
rootfs/usr/bin/wificam-camera-ctl

scripts/build_kernel.sh
scripts/package_rootfs_overlay.sh
scripts/prepare_sd.sh
scripts/build_all.sh
```

## Why BusyBox httpd + CGI

T23/T23N devices are memory- and flash-constrained. The first firmware version does not need Node.js or Python on-device. BusyBox `httpd` serves static HTML/JS/CSS and executes a tiny shell CGI.

## Menu

- Dashboard
- Live view
- Recording
- Image
- Network / Wi‑Fi
- Storage / SD
- System
- Firmware update
- Logs

## API

```text
GET  /cgi-bin/api?op=status
GET  /cgi-bin/api?op=wifi_scan
POST /cgi-bin/api?op=wifi_apply    ssid=...&password=...
GET  /cgi-bin/api?op=storage
GET  /cgi-bin/api?op=camera_start
GET  /cgi-bin/api?op=camera_stop
GET  /cgi-bin/api?op=record_start
GET  /cgi-bin/api?op=record_stop
GET  /cgi-bin/api?op=reboot
```

Wi‑Fi switching creates a new profile, runs DHCP, and rolls back to `wpa_supplicant.conf.last-good` if no IPv4 address is obtained.

The Wi‑Fi password is processed through `wpa_passphrase`; the plaintext `#psk=` comment is removed before the file is stored.

## Camera and ISP integration

`wificam-camera-ctl` is the abstraction layer. Board/sensor-specific ISP and encoder commands are configured in:

```text
/etc/wificam/wificam.conf
```

Once the exact image sensor and camera userspace are validated, start/stop/snapshot/record commands can be connected without changing the web UI.

## Security

The current CGI is a laboratory/trusted-LAN scaffold. Add web authentication and CSRF protection before permanent deployment. Remote reboot is disabled by default (`ALLOW_REBOOT=0`).

Do not expose this interface directly to the public Internet.
