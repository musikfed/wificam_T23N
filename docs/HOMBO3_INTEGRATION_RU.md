# PegineLab WIFICAM T23N → Hombo3 (Hombo3_3.0.0)

Цель — локальная автономная IP Wi-Fi камера для Hombo3/YOLO/VectorProbe,
а в дальнейшем для визуального LLM-агента. Камера загружается только с SD.
SSH/Dropbear **обязательно сохраняется**.

## Порты / процессы

| Функция | Endpoint | Предусловие |
|---|---|---|
| PegineLab UI | `http://CAMERA_IP:8090/` | BusyBox httpd + Basic Auth |
| JSON API | `http://CAMERA_IP:8090/cgi-bin/api?op=status` | исполняющийся BusyBox CGI, не текст `#!/bin/sh` |
| JPEG кадр | `http://CAMERA_IP:8090/cgi-bin/snapshot.jpg` | CGI + `rvd`/raptorctl |
| RTSP | `rtsp://CAMERA_IP:554/ch0` | `rsd` + `rvd`; адрес/порт проверить |
| Микрофон | RTSP audio track | `rad` + RTSP, подтверждение `ffprobe` |
| ONVIF | `http://CAMERA_IP/onvif/device_service` | ONVIF discovery/сервер |
| Динамик | `play -s -r 16000 -` через SSH | `rac` + Raptor audio-out + динамик |
| SSH recovery | TCP 22 | Dropbear, `SSH_PROTECT=1` |

## Почему предыдущая PegineLab UI показала API offline

Старый `0.1_test` выдавал содержимое файла `#!/bin/sh` на запрос к
`/cgi-bin/api` вместо JSON. Сама HTML/CSS-оболочка работала, но всё,
что зависело от CGI (status, кнопки, preview), не работало.

В текущих исходниках:
- BusyBox для MIPS **принудительно пересобирается** перед `rootfs.ext2`;
- в конфиге требуются `CONFIG_HTTPD`, `CONFIG_FEATURE_HTTPD_CGI`,
  `CONFIG_FEATURE_HTTPD_BASIC_AUTH`;
- startup `S90wificam` проверяет, что authenticated `/cgi-bin/api?op=status`
  реально вернул JSON, и останавливает httpd при выдаче исходника CGI;
- фронтенд явно сообщает об отключённом CGI вместо `Unexpected token '#'`.

Эти изменения ещё требуют **новой сборки SD image и аппаратной проверки**.
Готовый релиз `0.1_test` остаётся неизменным.

## Диагностика старой карты через SSH (ничего не менять)

В WSL на Acer:

```sh
cd ~/myipcam/wificam_T23N
git switch mymarrchWFcam
git pull --ff-only origin mymarrchWFcam
scp -O scripts/camera_diagnostics.sh root@192.168.1.55:/tmp/
ssh root@192.168.1.55
```

На камере (пароль передаётся только локально, в командной строке для теста):

```sh
WEB_PASSWORD='ВАШ_ПАРОЛЬ' sh /tmp/camera_diagnostics.sh
pidof rvd rad rsd rhd
microphone status
speaker status
command -v rac
command -v play
raptorctl config get audio enabled
raptorctl config get audio ao_enabled
raptorctl config get rtsp port
raptorctl config get rtsp backchannel
```

Не запускать `killall httpd`, не отключать `rvd/rad/rsd` и не выключать SSH.

## Hombo3 на компьютере

Репозиторий `musikfed/Hombo3_3.0.0` получил профиль
`.env.wificam.example`, диагностическую утилиту
`scripts/probe_wificam.py`, HTTP JPEG fallback, опциональную защищённую
передачу Hombo TTS в динамик камеры через SSH.

Тест на Acer:

```sh
python scripts/probe_wificam.py --ip 192.168.1.55
```

В режиме `CAMERA_VIDEO_BACKEND=http_snapshot` Hombo3 использует
авторизованные JPEG кадры; в режиме `auto` — RTSP/FFmpeg. Микрофон идёт
по RTSP/FFmpeg при наличии реальной audio track. Камера не запускает LLM
в 36 MiB оперативной памяти: зрение/агент работают на Acer/сервере.

Для TTS на динамик без открытых HTTP-команд поддерживается только явное
включение `SPEECH_OUTPUT=camera_ssh` после настройки SSH-ключа и
аппаратного теста `play`. По умолчанию Hombo3 продолжает говорить через
ESP32. Также возможен ONVIF RTSP backchannel, если он реально доступен,
но это отдельный тест.

Не публиковать SSH, RTSP, ONVIF или PegineLab Web UI в Интернет; управление
только в доверенной LAN/VPN. Тестовый `admin/Wificam12345` публично известен
— для постоянной работы его нужно заменить.

## Скорость реакции / управление PTZ (новый SD build)

В `http://CAMERA_IP:8090/` вкладка «Видео» теперь использует
`/cgi-bin/live.mjpg`: один долгоживущий Raptor RHD MJPEG-поток без
повторного запуска кодирования JPEG каждые 2 секунды. При ошибке
автоматически используется `/cgi-bin/snapshot.jpg` раз в 2 секунды.
При закрытии вкладки поток разрывается для экономии CPU/RAM.

В `/cgi-bin/api` добавлены `ptz_status` (GET), `ptz_move` (POST,
`direction=left|right|up|down`) и `ptz_invert` (POST,
`axis=pan|tilt&enabled=0|1`). Все изменения требуют HTTP Basic Auth
и CSRF. Реальное управление возможно **только при работающем
`motors-daemon`**. Реверс хранится в `/opt/wificam/ptz-controls.conf`,
не требует остановки видеосервиса или повторной загрузки драйверов.
Один клик — шаг не более 150 тиков (по умолчанию 50).

У Galayou G2 профиль содержит моторы, **но это не подтверждает
работоспособность их проводки на конкретном экземпляре**. Автофокус
и оптический зум в прошивке PegineLab помечаются недоступными,
пока на оборудовании не появится поддерживаемый драйвер; зум
картинки в браузере цифровой. В Hombo3 оптический зум и Imaging AUTO
передаются ONVIF при наличии соответствующих возможностей.

Не отключать `rvd`, `rad`, `rsd`, `rhd`, `motors-daemon`, Wi-Fi,
Dropbear, MMC, ISP или ядро: это **основа** потокового видео, аудио
и восстановления. Ускорение идёт за счёт уменьшения лишних
переинициализаций JPEG и сохранения только последнего кадра.

В pinned Raptor JPEG FPS по умолчанию может быть **1**, даже если
RTSP stream0 работает на 25 FPS. Сначала измерить `raptorctl config
get jpeg fps`. Для обратимой настройки 8–15 FPS:

```sh
# На Acer (WSL):
scp -O scripts/camera_preview_fps.sh root@192.168.1.55:/tmp/
# На камере по SSH:
sh /tmp/camera_preview_fps.sh show
sh /tmp/camera_preview_fps.sh apply 12
# Следующую команду только при готовом доступе по SSH:
# /etc/init.d/S31raptor restart
# Для отката:
# sh /tmp/camera_preview_fps.sh restore
```

Скрипт не перезапускает Raptor сам и не выгружает модули ядра.
После изменения FPS проверить CPU, нагрузку, температуру, кадры,
аудио и motor PTZ. Если растёт задержка или теряются кадры —
откатить FPS.

## Где работают проекты (важно для всех инструкций)

WIFICAM собирается на Acer в **WSL Ubuntu 24.04 на Windows диске D:**,
а Hombo3/CameraHub запускаются **не в WSL, а в Windows 11 Pro на Acer**.
`.109` — DEXP с AmneziaWG и Docker Compose, `.100` — GPU CORE для LLM.
Остальная архитектура, CPU, RAM, Python/uv и правила безопасности:
[PEGINELAB_LAB_ARCHITECTURE_RU.md](PEGINELAB_LAB_ARCHITECTURE_RU.md).

## Ориентация и речь для Hombo3

Зеркалирование/переворот и digital zoom в вебморде T23N меняют
**только браузерный просмотр**; pan/tilt reverse настраивается
отдельно, сохраняется и влияет на физический привод мотора.
Для Hombo3 есть отдельные mirror/flip, ручной ONVIF focus near/far
(короткий импульс + Stop), запрос автофокуса и оптического zoom.
Аппаратная фокусировка и оптический zoom на Galayou G2 не доказаны.

Голосовой контур Hombo3: микрофон RTSP → Acer Windows FFmpeg →
доверенный Whisper-STT `.100` → Ollama LLM → Acer SAPI TTS →
динамик T23N через SSH `play/rac`. Это opt-in ручное 5-секундное
распознавание, по умолчанию выключено. До проверки реальной
аудиодорожки и динамика не называть это рабочим.
[Инструкция PTZ/аудио](https://github.com/musikfed/Hombo3_3.0.0/blob/main/docs/CAMERA_PTZ_AUDIO_RU.md).
