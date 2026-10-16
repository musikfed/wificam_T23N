# Web UI and API — English

Minimal embedded web stack for T23/T23N:

```text
BusyBox httpd
  └─ HTML/CSS/JS
      └─ CGI JSON API
          ├─ Wi-Fi/IP
          ├─ Camera service
          ├─ MEDIA storage
          └─ SSH/WireGuard/AmneziaWG toggles
```

## Files

```text
web/index.html
web/styles.css
web/app.js
web/cgi-bin/api

rootfs/etc/init.d/S90wificam
rootfs/etc/init.d/S91wificam-services
rootfs/etc/wificam/wificam.conf
rootfs/usr/bin/wificam-camera-ctl
rootfs/usr/bin/wificam-service-ctl
rootfs/usr/bin/wificam-set-web-password
```

## Camera

Sensor discovery belongs to the OS at boot. `wificam-camera-ctl` does not identify the sensor model; it only talks to an already initialized camera service or its init hook.

## API

```text
GET  /cgi-bin/api?op=status
GET  /cgi-bin/api?op=wifi_scan
POST /cgi-bin/api?op=wifi_apply
GET  /cgi-bin/api?op=storage
GET  /cgi-bin/api?op=services
POST /cgi-bin/api?op=service_toggle
POST /cgi-bin/api?op=camera_start
POST /cgi-bin/api?op=camera_stop
POST /cgi-bin/api?op=record_start
POST /cgi-bin/api?op=record_stop
POST /cgi-bin/api?op=web_password
POST /cgi-bin/api?op=reboot
```

Mutating operations use POST + a per-boot CSRF token.

## Web password

The Web UI does not start without a password by default:

```sh
printf '%s' 'MY_NEW_PASSWORD' | wificam-set-web-password admin
/etc/init.d/S90wificam start
```

## Optional services

SSH, WireGuard and AmneziaWG are disabled by default. The Web UI can start them and persist an autostart marker. Disabling stops the process/interface.

This is intended for a trusted camera LAN. Public Internet exposure requires additional TLS/auth hardening.
