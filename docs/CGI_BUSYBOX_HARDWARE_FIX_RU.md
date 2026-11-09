# Подтверждённый дефект CGI на реальной T23N — ремонт без пересборки ядра

**Наблюдение 2026-11-02** на загруженной с SD \`galayou_g2_t23n_sc2336_atbm6012bx\`:
- \`root=/dev/mmcblk0p2 rootfstype=ext4\`, Wi-Fi и SSH функционируют;
- \`/usr/share/wificam-web/index.html\`, \`/etc/init.d/S90wificam\`, CGI API присутствуют;
- \`sh /usr/share/wificam-web/cgi-bin/api\` возвращает корректный JSON;
- **оба** \`httpd\` и \`busybox httpd\` на loopback \`127.0.0.1:18090\` возвращали \`HTTP/1.1 200\` и **буквальный текст \`#!/bin/sh\` вместо выполнения CGI**;
- старт WIFICAM отказал с \`WIFICAM CGI FAILED ... refusing to expose CGI source\`, порт \`8090\` остался закрыт.

Это реальная проблема **скомпилированного BusyBox httpd**, а не неисправность Linux/ядра, Wi-Fi, SD-разметки или самого \`cgi-bin/api\`. Наличие \`CONFIG_FEATURE_HTTPD_CGI=y\` в исходной \`.config\` **не доказывает** наличия CGI в установленном бинарнике. Вместе с CGI обязательно выключать \`CONFIG_FEATURE_FORCE_APPLETS\`: CGI требует \`execv\`.

## Что добавлено в ветку

1. \`scripts/rebuild_busybox_cgi_candidate.sh\` — **только** \`br-busybox-reconfigure\` и \`br-busybox-rebuild\` в уже существующем Thingino; **не компилирует ядро и не пересоздаёт SD**. Складывает новый кандидат в игнорируемое \`out/candidate-busybox/busybox-cgi-candidate\`.
2. \`scripts/camera_smoke_httpd_cgi.sh\` — запускает переданный кандидат только на \`127.0.0.1:18090\` камеры, проверяет точный JSON, замечает публикацию CGI-исходника; по завершении убирает временные файлы и останавливает тестовый сервер. Не трогает штатный \`/bin/busybox\`.
3. \`rootfs/etc/init.d/S90wificam\` — **до** открытия публичного 8090 тестирует CGI через localhost; если CGI не работает, отказывает в запуске. Для проверенного отдельно бинарника допускает \`WIFICAM_HTTPD_BIN=/opt/wificam/.../busybox\` (абсолютный путь), не заменяя базовый BusyBox.
4. Тесты CI проверяют сохранение защитного механизма и синтаксис, но **не заменяют аппаратный CGI-тест**.

## Исправленная ошибка сборки от 02.11.2026

При первой попытке на Huananzhi запуск дошёл до `br-busybox-reconfigure`
и был остановлен самим Buildroot:

```text
You seem to have the current working directory in your
LD_LIBRARY_PATH environment variable. This doesn't work.
make: *** [br-busybox-reconfigure] Error 2
```

Причина: у терминала Ubuntu унаследована несовместимая с Buildroot
`LD_LIBRARY_PATH` (например `.`, текущий каталог или пустой компонент
из `:`). **Исправлено в `scripts/rebuild_busybox_cgi_candidate.sh`:**
переменная сбрасывается только внутри процесса скрипта и его дочерних
`make`. Не нужно менять глобальный профиль, системные библиотеки
или выполнять `sudo`. Это **не** ошибка камеры, BusyBox CGI
или ядра; до компиляции тогда не дошло.

Если в `"$JOB/out/rebuild_busybox_cgi_candidate.sh"` лежит предыдущая
версия скрипта, его **обязательно скачать заново** из GitHub перед повтором.
Старый файл сам не обновится после `git fetch`. Если нужно одноразово
обойти ошибку старым скриптом: `env -u LD_LIBRARY_PATH sh "$JOB/out/rebuild_busybox_cgi_candidate.sh"`,
но предпочтительнее свежий исправленный скрипт ниже.

## Шаг A. Инкрементально собрать только BusyBox на Huananzhi

Выполнять от обычного пользователя Ubuntu на сервере, **не sudo**, только когда YadroKreator не собирает ничего другого.

В команде ниже указан уже успешно собранный worktree камеры. Он хранит настройки именно той сборки и \`out/thingino-user\`, которые понадобятся Buildroot:

\`\`\`bash
JOB=/1tbdisk/PegineLab/build/jobs/1a383b6c22584fc1a3c4f0c4e80d20a3/wificam_T23N
SOURCE=/1tbdisk/PegineLab/projects/wificam_T23N

test -f "$JOB/out/thingino-user/galayou_g2_t23n_sc2336_atbm6012bx/busybox-wificam.fragment"
git -C "$SOURCE" fetch origin mymarrchWFcam
git -C "$SOURCE" show origin/mymarrchWFcam:scripts/rebuild_busybox_cgi_candidate.sh \
  > "$JOB/out/rebuild_busybox_cgi_candidate.sh"
sh "$JOB/out/rebuild_busybox_cgi_candidate.sh"
\`\`\`

Скрипт проверяет отсутствие активных задач YadroKreator, BusyBox fragment и итоговую \`.config\`, собирает BusyBox **без запуска полной команды \`build_thingino_wificam_image.sh\`**. В случае отказа не пытайтесь насильно \`make cleanbuild\`: пришлите последние сообщения. Это тестовый кандидат; **ещё не новый образ для SD**.

После завершения запишет путь и SHA256:
\`\`\`text
.../out/candidate-busybox/busybox-cgi-candidate
.../out/candidate-busybox/busybox-cgi-candidate.sha256
\`\`\`

## Шаг B. Проверить кандидат на камере, не заменяя систему

Если сервер имеет маршрут к \`192.168.1.55\`, с Huananzhi:
\`\`\`bash
scp "$JOB/out/candidate-busybox/busybox-cgi-candidate" \
  root@192.168.1.55:/tmp/wificam-busybox-cgi
scp "$SOURCE/scripts/camera_smoke_httpd_cgi.sh" \
  root@192.168.1.55:/tmp/camera_smoke_httpd_cgi.sh
\`\`\`

Если Huananzhi не видит сеть \`192.168.1.0/24\`, передать оба файла **через ПК Windows, который видит и сервер, и камеру**. Нельзя пытаться исправлять это открытием порта 8090 в интернет.

В SSH на **самой камере**:
\`\`\`sh
chmod 700 /tmp/wificam-busybox-cgi
sh /tmp/camera_smoke_httpd_cgi.sh /tmp/wificam-busybox-cgi
\`\`\`

Только строка \`PASS: candidate BusyBox httpd EXECUTED CGI\` является успешным тестом. \`FAIL\` или \`CGI SOURCE EXPOSED\` — не запускать этот бинарник на 8090.

Тест не затрагивает \`/bin/busybox\`, SSH, SD или порты 80/443. Временный кандидат исчезнет после перезагрузки, поэтому **это ещё не постоянное исправление**.

## Шаг C. После PASS — временно поднять наше меню для проверки

Перенеси проверенный \`rootfs/etc/init.d/S90wificam\` из новой ветки в \`/tmp/S90wificam-cgi\` на камере, затем в SSH:

\`\`\`sh
WIFICAM_HTTPD_BIN=/tmp/wificam-busybox-cgi sh /tmp/S90wificam-cgi start
netstat -lnt 2>/dev/null | grep ':8090'
\`\`\`

Этот скрипт сначала повторит **локальную** проверку CGI, и только затем разрешит открыть \`8090\`. Файл авторизации \`/opt/wificam/httpd.conf\` остаётся прежним, не печатайте его содержимое и пароли. Открой \`http://192.168.1.55:8090/\` с доверенного компьютера и проверь реальный ответ API, затем снимок SC2336 и видео.

Для окончательного выпуска **ещё** нужно закрепить проверенный CGI-бинарник в SD-rootfs, протестировать холодный старт, проверить SSH/RTSP/PTZ и сохранить прежнюю рабочую SD. Не изменять \`/bin/busybox\` напрямую.

## Какой статус считать успешным

- GitHub CI — проверены сценарии/синтаксис, **не** камера.
- Инкрементальный BusyBox собран — есть кандидат, **не** CGI-вердикт.
- Тест CGI на loopback выдаёт \`PASS\` — бинарник на этой камере умеет CGI.
- Сервис на \`:8090\` возвращает не скрипт, а JSON после авторизации — отдельная пользовательская проверка.
- Перезагрузка со второй SD и все функции камеры проходят — только тогда выпускать следующую версию.

См. [первый запуск](REAL_CAMERA_FIRST_BOOT_RU.md), [Web Stack](WEB_STACK_RU.md), [сборка и образ](BUILD_RU.md).

## Повторное аппаратное испытание 9 ноября 2026 — CGI preflight

Новая SD-прошивка WifCam Helper действительно загрузилась: ядро
`3.10.14__isvp_pike_1.0__`, Wi-Fi `192.168.1.55`, SSH и маркер
`PEGINELAB_HELPER_FIRMWARE_V1` подтверждены. Но :8090 остался закрыт с
`WIFICAM CGI PRE-FLIGHT FAILED`. На устройстве `busybox --list` показывает
`httpd`, но не `wget`; наличие `curl` отдельно ещё не установлено.
Изначальный тест сообщал один и тот же текст для неисправного CGI и
отсутствующего HTTP-клиента. На :18090 остался тестовый `httpd`.

**Исправлено в исходниках для следующей новой сборки:**
- Добавлен `CONFIG_WGET=y` в BusyBox-фрагмент и список обязательных опций
  перед пересборкой BusyBox/SD. Это позволяет получить HTTP JSON на loopback
  даже на минимальном образе без curl.
- `S90wificam` отдельно сообщает об отсутствии клиента
  `WIFICAM CGI PRE-FLIGHT UNAVAILABLE`, не обвиняя CGI ошибочно.
- `run_httpd()` использует `exec`, чтобы PID фонового preflight соответствовал
  процессу HTTP-сервера, который можно завершить; не используется `killall`.
- Защита остаётся: если реальный CGI не исполняется, :8090 не открывается.

**Не заявлять, что ошибка устранена на железе до повторного испытания.**
Потребуется новая сборка YadroKreator c полной компиляцией ядра и rootfs,
новая SD и тест на камере:

```sh
command -v curl || true
command -v wget || true
busybox --list | grep -E '^(httpd|wget)$'
netstat -lnt | grep 8090
tail -n 40 /var/log/wificam-httpd.log
```

Если после включения клиента CGI всё ещё выдаёт `#!/bin/sh` вместо
`{"ok":true,...}`, исправлять непосредственно бинарник BusyBox/httpd,
не обходить блокировку :8090.
