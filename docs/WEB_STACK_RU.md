# Web UI и API — русский

Этот каталог содержит уже не макет, а минимальный рабочий каркас web-интерфейса для T23/T23N.

## Что входит

```text
web/index.html            меню камеры
web/styles.css            адаптивный интерфейс
web/app.js                работа UI с API
web/cgi-bin/api           BusyBox CGI JSON API

rootfs/etc/init.d/S90wificam
rootfs/etc/wificam/wificam.conf
rootfs/usr/bin/wificam-camera-ctl

scripts/build_kernel.sh
scripts/package_rootfs_overlay.sh
scripts/prepare_sd.sh
scripts/build_all.sh
```

## Почему BusyBox httpd + CGI

На T23/T23N мало RAM и flash. Для первой версии не нужен Node.js/Python на камере. BusyBox `httpd` отдает статический HTML/JS/CSS и запускает маленький shell CGI.

## Меню

- Главная / Dashboard
- Видео / Live view
- Запись / Recording
- Изображение / Image
- Сеть / Wi‑Fi
- SD-карта / Storage
- Система / System
- Обновление / Firmware
- Логи / Logs

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

Смена Wi‑Fi использует временный новый профиль, DHCP-проверку и rollback к `wpa_supplicant.conf.last-good`, если новый профиль не дал IPv4.

Пароль Wi‑Fi прогоняется через `wpa_passphrase`; строка с исходным `#psk=` удаляется перед сохранением.

## Камера и ISP

`wificam-camera-ctl` является слоем абстракции. Реальные команды сенсора/ISP/encoder задаются в:

```text
/etc/wificam/wificam.conf
```

После определения сенсора и userspace камеры туда подключаются команды запуска видео, snapshot и записи. Web UI менять не потребуется.

## Безопасность

Текущий CGI — каркас для доверенной локальной сети и лабораторной загрузки. Перед постоянным использованием необходимо добавить web-аутентификацию и CSRF-защиту. Поэтому удаленная перезагрузка по умолчанию заблокирована (`ALLOW_REBOOT=0`).

Не публиковать этот интерфейс напрямую в Интернет.
