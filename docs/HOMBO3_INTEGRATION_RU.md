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
