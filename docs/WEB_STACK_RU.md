# Web UI и API — русский

Это минимальный рабочий каркас web-интерфейса для T23/T23N.

## Что входит

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

## Запуск Web UI

По умолчанию интерфейс **не стартует без пароля**. После загрузки по UART/console:

```sh
printf '%s' 'МОЙ_НОВЫЙ_ПАРОЛЬ' | wificam-set-web-password admin
/etc/init.d/S90wificam start
```

BusyBox `httpd` запускается с `/data/httpd.conf`. После этого браузер запросит Basic Auth пользователя `admin`.

Для разового лабораторного теста можно установить `ALLOW_UNAUTHENTICATED_WEB=1`, но это не рекомендуется.

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

Все изменяющие POST-запросы используют per-boot CSRF token, который UI получает из `status`.

## Wi‑Fi

Новая сеть сначала записывается во временно применяемый профиль. После запуска `wpa_supplicant` выполняется DHCP. Если IPv4 не получен, backend возвращает `wpa_supplicant.conf.last-good`.

`wpa_passphrase` используется для получения PSK; строка-комментарий с исходным паролем удаляется перед сохранением.

## Камера и ISP

`wificam-camera-ctl` — слой между web API и конкретным camera userspace. Команды сенсора/ISP/encoder задаются в `/etc/wificam/wificam.conf` после определения точного сенсора.

## Пароль Web UI

В меню **Система** можно сменить пароль администратора. Операция разрешается только уже аутентифицированному пользователю и после CSRF-проверки. После изменения `httpd` перезапускается.

Текущая защита BusyBox Basic Auth/MD5-crypt предназначена для локальной сети камеры. Для публикации устройства в Интернет потребуется более современный auth/session backend, TLS и полноценная hardening-модель.
