# Web UI and API — English

This is the minimal working embedded web stack for T23/T23N.

## Included

```text
web/index.html
web/styles.css
web/app.js
web/cgi-bin/api
rootfs/etc/init.d/S90wificam
rootfs/etc/wificam/wificam.conf
rootfs/usr/bin/wificam-camera-ctl
rootfs/usr/bin/wificam-set-web-password
scripts/build_kernel.sh
scripts/package_rootfs_overlay.sh
scripts/prepare_sd.sh
scripts/build_all.sh
```

## Starting the Web UI

By default the interface **does not start without a password**. After booting, use UART/console:

```sh
printf '%s' 'MY_NEW_PASSWORD' | wificam-set-web-password admin
/etc/init.d/S90wificam start
```

BusyBox `httpd` then starts with `/data/httpd.conf` and the browser requests Basic Authentication for user `admin`.

For a one-off lab test, `ALLOW_UNAUTHENTICATED_WEB=1` can be enabled, but it is not recommended.

## API

```text
GET  /cgi-bin/api?op=status
GET  /cgi-bin/api?op=wifi_scan
POST /cgi-bin/api?op=wifi_apply
GET  /cgi-bin/api?op=storage
POST /cgi-bin/api?op=camera_start
POST /cgi-bin/api?op=camera_stop
POST /cgi-bin/api?op=record_start
POST /cgi-bin/api?op=record_stop
POST /cgi-bin/api?op=web_password
POST /cgi-bin/api?op=reboot
```

All mutating POST requests require a per-boot CSRF token obtained by the UI from `status`.

## Wi‑Fi

The new network is applied first and DHCP is attempted. If no IPv4 address is obtained, the backend restores `wpa_supplicant.conf.last-good`.

`wpa_passphrase` generates the PSK; its plaintext password comment is removed before persistence.

## Camera and ISP

`wificam-camera-ctl` separates the web API from board-specific camera userspace. Sensor/ISP/encoder commands are configured in `/etc/wificam/wificam.conf` once the exact sensor is known.

## Web UI password

The **System** page can change the administrator password. The operation requires an already authenticated user plus the CSRF token. `httpd` restarts after the change.

BusyBox Basic Auth/MD5-crypt is intended here as a local-camera-network bootstrap. Internet exposure requires a modern authentication/session backend, TLS and additional hardening.
