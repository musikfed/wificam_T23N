# Web UI и API — русский

Минимальный embedded web-стек для T23/T23N:

```text
BusyBox httpd
  └─ HTML/CSS/JS
      └─ CGI JSON API
          ├─ Wi-Fi/IP
          ├─ Camera service
          ├─ MEDIA storage
          └─ SSH/WireGuard/AmneziaWG toggles
```

## Файлы

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

## Камера

Определение сенсора выполняет ОС при загрузке. `wificam-camera-ctl` не определяет модель сенсора; он только использует уже поднятый системный camera service либо его init hook.

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

Изменяющие операции используют POST + per-boot CSRF token.

## Web password

По умолчанию Web UI не стартует без пароля:

```sh
printf '%s' 'МОЙ_НОВЫЙ_ПАРОЛЬ' | wificam-set-web-password admin
/etc/init.d/S90wificam start
```

## Дополнительные сервисы

SSH, WireGuard и AmneziaWG выключены по умолчанию. Web UI может включить их сейчас и оставить marker для следующей загрузки. При выключении процесс/интерфейс останавливается.

Это рассчитано на локальную сеть камеры. Публичный Интернет требует дополнительного TLS/auth hardening.
