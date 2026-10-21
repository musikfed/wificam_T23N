# Оптимизация загрузки T23N / PegineLab WIFICAM

## Измеренный baseline на рабочем SD boot

Аппаратный запуск 2026-10-21:

```text
RAM total        : 36632 KiB
used             : 14128 KiB
free             : 8656 KiB
buff/cache       : 13848 KiB
rootfs           : 54.7 MiB
rootfs used      : 16.7 MiB (33%)
rootfs available : 33.6 MiB
swap             : 0
```

По памяти аварийной ситуации нет. Сначала нужно довести PegineLab WIFICAM до
полностью рабочего состояния, затем уменьшать набор сервисов.

## Raptor: что нельзя выключать вслепую

На профиле `galayou_g2_t23n_sc2336_atbm6012bx` фактически используется
Thingino Raptor.

Оставлять до завершения аппаратной проверки:

```text
rvd   sensor/video capture — основной источник видео
rhd   HTTP JPEG/MJPEG — нужен PegineLab preview
rsd   RTSP
rad   microphone/speaker
ric   IR-cut/day-night
rod   OSD
motors-daemon — PTZ
wpa_supplicant/udhcpc — сеть
dropbear — SSH во время отладки
```

PegineLab теперь понимает Raptor напрямую:
- status считает `rvd` работающей камерой;
- snapshot использует `raptorctl rvd save jpeg ... 0`;
- Prudynt для этого профиля не требуется.

## Почему Thingino preview показывает 502 / backend_unreachable

Штатный `preview.html` Raptor пытается работать с WebRTC backend (обычно
порт 8554). На проверенной сборке процесс RWD/WebRTC не запущен, поэтому его
502 не является признаком падения sensor/video pipeline.

PegineLab не должна зависеть от RWD: её preview использует snapshot через RVD.

## Кандидаты на оптимизацию ПОСЛЕ проверки PegineLab

Только после подтверждения:
- `http://CAMERA_IP:8090/` открывается;
- status API работает;
- snapshot показывает изображение;
- PTZ/IR/аудио проверены по требуемому набору функций.

Можно рассматривать:

1. штатный Thingino `S90httpd`, если больше не нужен fallback UI на port 80;
2. `S50httpd-ssl`, если штатный HTTPS Thingino не нужен;
3. ONVIF discovery/notifier, только если ONVIF не используется;
4. `mdnsd`, только если mDNS discovery не нужен;
5. `raptor-motion-watch`, только если motion detection/alerts не нужны;
6. `crond`, только после проверки отсутствия нужных cron jobs.

Не отключать весь Raptor и не удалять `rvd`.

## Перед каждой оптимизацией

```sh
free
df -h
ps w
netstat -lntp 2>/dev/null
pidof rvd rhd rsd rad ric rod motors-daemon
```

После одного изменения — reboot и повторная проверка. Не отключать сразу
несколько подсистем: иначе невозможно понять, что сломало camera pipeline.

## Приоритет оптимизации

1. Сначала PegineLab authentication + port 8090.
2. Затем Raptor snapshot/API integration.
3. Затем отключение дублирующего stock Thingino HTTP/HTTPS.
4. Потом необязательные discovery/motion services.
5. Только в последнюю очередь — build-time сокращение набора Raptor daemons.

Build-time минимизация Raptor должна выполняться отдельным hardware-tested
релизом, а не внутри первого рабочего 0.1_test.
