# Web UI and API — English

PegineLab WIFICAM is a mandatory web stack in the canonical Thingino MMC/SD image for T23/T23N:

```text
Thingino Web UI         : 80/443
PegineLab WIFICAM httpd : 8080
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


## Thingino integration

The canonical Thingino image is built by
`scripts/build_thingino_wificam_image.sh`. The script enables BusyBox
`httpd`, embeds WIFICAM directly in `p2/rootfs.ext2`, and refuses to publish
the image unless `debugfs` confirms the Web UI exists inside the ext4 rootfs.

The Thingino camera backend is supported through Prudynt:

```text
service              /etc/init.d/S31prudynt
snapshot             prudyntctl snapshot -c 0
recording            Thingino record / /run/prudynt/mp4ctl
WIFICAM live preview /cgi-bin/snapshot.jpg
```

Persistent WIFICAM state is kept under `/opt/wificam`. Storage prefers a
dedicated `/mnt/media`; for the first Thingino hardware test it can fall back
to an SD mount already owned by the OS (`/mnt/mmcblk0p1`, `/mnt/sdcard`,
`/mnt/sda0`).

Hardware acceptance requires both the normal Thingino UI and **PegineLab
WIFICAM at `http://CAMERA_IP:8080/`**.
