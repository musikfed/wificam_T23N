## Тестовый вход 0.1_test

Для текущей тестовой ветки PegineLab WIFICAM использует заранее известные
LAN-only реквизиты:

```text
URL:      http://CAMERA_IP:8090/
login:    admin
password: Wificam12345
```

Это **не production-настройка**. Она введена специально для аппаратной
отладки, чтобы исключить несовместимость MD5-crypt BusyBox/uClibc и каждый
раз гарантированно попадать в Web UI.

В сборке:

```text
AUTO_PROVISION_TEST_WEB_AUTH=1
DEFAULT_WEB_USER=admin
DEFAULT_WEB_PASSWORD=Wificam12345
AUTH_PASSWORD_MODE=plain
```

Если `/opt/wificam/httpd.conf` отсутствует, `S90wificam` создаёт его
автоматически. После входа пароль можно сменить в разделе **Система**.

Для production вернуть first-boot страницу:

```sh
sed -i 's/^AUTO_PROVISION_TEST_WEB_AUTH=.*/AUTO_PROVISION_TEST_WEB_AUTH=0/' /etc/wificam/wificam.conf
rm -f /opt/wificam/httpd.conf
/etc/init.d/S90wificam restart
```

# PegineLab WIFICAM — первый запуск, авторизация и SSH

## Web endpoints

```text
Thingino stock UI : http://CAMERA_IP/ или https://CAMERA_IP/
Thingino login    : root
Thingino password : root

Thingino camera/API backend : TCP 8080
PegineLab WIFICAM           : http://CAMERA_IP:8090/
```

TCP 8080 занят штатным Thingino camera/API stack. PegineLab WIFICAM использует
TCP 8090.

## Первое включение PegineLab WIFICAM

В ветке `0.1_test` first-boot claim временно заменён детерминированным
LAN-only входом для аппаратной отладки:

```text
http://CAMERA_IP:8090/
login: admin
password: Wificam12345
```

Production-режим с отдельной страницей создания пароля сохранён в исходниках и
включается отключением test auto-provision.

Файл авторизации:

```text
/opt/wificam/httpd.conf
```

### Уже записанная 0.1_test карта

Для первого аппаратно проверенного image `f9f50a...` используйте готовый
recovery-скрипт — он повторяет **реально сработавший на камере** BusyBox
конфиг и не трогает SSH:

```powershell
scp -O .\scripts\camera_fix_wificam_0_1_test.sh root@CAMERA_IP:/tmp/
ssh root@CAMERA_IP "sh /tmp/camera_fix_wificam_0_1_test.sh"
```

или из Linux/WSL:

```sh
scp -O scripts/camera_fix_wificam_0_1_test.sh root@CAMERA_IP:/tmp/
ssh root@CAMERA_IP 'sh /tmp/camera_fix_wificam_0_1_test.sh'
```

Проверенный конфиг внутри скрипта:

```text
H:/usr/share/wificam-web
/:admin:Wificam12345
```

## SSH из Windows PowerShell

Thingino использует Dropbear SSH.

```powershell
ssh root@192.168.1.55
```

Пароль текущего профиля по умолчанию:

```text
root
```

### REMOTE HOST IDENTIFICATION HAS CHANGED

После перепрошивки SSH host key может измениться. Если камера была
перепрошита вами и IP остался тем же, удалить старую запись:

```powershell
ssh-keygen -R 192.168.1.55
```

или явно для Windows-файла:

```powershell
ssh-keygen -f "$env:USERPROFILE\.ssh\known_hosts" -R 192.168.1.55
```

После этого:

```powershell
ssh root@192.168.1.55
```

Проверить новый fingerprint, ответить `yes`, затем ввести пароль.

Если перепрошивки не было и host key сменился неожиданно, старый ключ
автоматически не удалять: сначала убедиться, что IP принадлежит нужной камере.

## SSH из Linux / Ubuntu / WSL

```sh
ssh root@192.168.1.55
```

После ожидаемой перепрошивки:

```sh
ssh-keygen -R 192.168.1.55
ssh root@192.168.1.55
```

Пароль по умолчанию: `root`.

Thingino использует Dropbear. Если обычный `scp` пытается использовать SFTP
и не работает, включить legacy SCP protocol:

```sh
scp -O file root@192.168.1.55:/tmp/
```

В Windows OpenSSH:

```powershell
scp -O .\file root@192.168.1.55:/tmp/
```

## Исправить порт WIFICAM без пересборки

Изменение 8080 -> 8090 — userspace-конфигурация. Kernel/U-Boot пересобирать
не требуется.

На камере:

```sh
grep '^WEB_PORT=' /etc/wificam/wificam.conf
sed -i 's/^WEB_PORT=.*/WEB_PORT=8090/' /etc/wificam/wificam.conf
/etc/init.d/S90wificam restart
sleep 2
netstat -lnt 2>/dev/null | grep ':8090'
cat /var/log/wificam-httpd.log
```

Если `sed` сообщает `Read-only file system`:

```sh
mount -o remount,rw /
sed -i 's/^WEB_PORT=.*/WEB_PORT=8090/' /etc/wificam/wificam.conf
/etc/init.d/S90wificam restart
```

## Типовые ошибки

### На :8080 открывается Raptor WebRTC

Это штатный Thingino backend. PegineLab открывать на:

```text
http://CAMERA_IP:8090/
```

### Connection refused на :8090

```sh
grep '^WEB_PORT=' /etc/wificam/wificam.conf
ps | grep '[h]ttpd'
netstat -lnt 2>/dev/null | grep -E ':8090|:8080'
cat /var/log/wificam-httpd.log
/etc/init.d/S90wificam restart
```

### Read-only file system

```sh
mount -o remount,rw /
```

### После установки пароля браузер снова просит login/password

Это нормальный HTTP Basic Auth PegineLab:

```text
login: admin
password: пароль PegineLab
```

Не путать со штатным Thingino `root/root`.

### SSH Permission denied

Использовать:

```text
user: root
password: root
```

если пароль root ранее не менялся.

### REMOTE HOST IDENTIFICATION HAS CHANGED

После ожидаемой перепрошивки:

```sh
ssh-keygen -R CAMERA_IP
```

Если смена ключа неожиданна — сначала проверить IP/устройство.

### WIFICAM httpd exited during startup

```sh
cat /var/log/wificam-httpd.log
netstat -lnt 2>/dev/null
busybox httpd -h 2>&1 | head
```

Актуальный PegineLab порт: 8090.


## Если на 8090 всё равно открывается Thingino/Raptor

Это диагностировано на первой аппаратной `0.1_test`. Причина была не в
порте 8090: старый PegineLab bootstrap запускал BusyBox `httpd` без `-c`.
BusyBox автоматически читал штатный Thingino `/etc/httpd.conf`, где есть:

```text
H:/var/www
P:/favicon.ico:...
P:/mjpeg:...
```

`H:/var/www` подменял наш `-h /usr/share/wificam-web`, поэтому именно
PegineLab-процесс на 8090 отдавал страницы Thingino.

Характерные строки:

```text
httpd: config error ... in '/etc/httpd.conf'
```

В актуальном коде bootstrap всегда получает отдельный пустой
`/opt/wificam/httpd-bootstrap.conf`, поэтому `/etc/httpd.conf` Thingino
вообще не читается.

### Быстро исправить уже записанную старую карту

Сначала убедиться, что PegineLab-файлы реально присутствуют:

```sh
grep -m1 -E 'PegineLab|WIFICAM' /usr/share/wificam-web/index.html
```

Затем создать PegineLab Basic Auth. Это одновременно переводит старый
`S90wificam` в ветку с явным `-c /opt/wificam/httpd.conf`:

```sh
printf '%s' 'НОВЫЙ_ПАРОЛЬ_МИНИМУМ_10' | wificam-set-web-password admin
```

Очистить старые ошибочно запущенные httpd и поднять обе веб-службы заново
(SSH-сессия при этом остаётся):

```sh
/etc/init.d/S90wificam stop 2>/dev/null || true
killall httpd 2>/dev/null || true
/etc/init.d/S90httpd start
/etc/init.d/S90wificam start
sleep 2
netstat -lntp 2>/dev/null | grep -E ':80|:8090'
curl -s http://127.0.0.1:8090/ | head -n 12
```

Открывать **корень**, не Thingino `/preview.html`:

```text
http://CAMERA_IP:8090/
login: admin
password: заданный выше
```

Thingino остаётся отдельно на 80/443.

## BusyBox: od: invalid option -- A

Первая версия использовала GNU-совместимый вызов `od -An -N16 -tx1`, но
BusyBox `od` в этом образе не поддерживает `-A/-N`. В актуальном
`S90wificam` CSRF генерируется переносимо:

```sh
dd if=/dev/urandom bs=32 count=1 2>/dev/null | sha256sum
```

Пересборка ядра для этого не требуется.


## SSH — обязательный локальный recovery-канал

Для `0.1_test` Dropbear на TCP 22 считается частью acceptance criteria.
В `/etc/wificam/wificam.conf` установлено:

```text
SSH_PROTECT=1
```

Поэтому PegineLab Web UI не должна выключать SSH. Это сделано специально для
локального/безоблачного владения камерой: даже если Web UI или camera service
сломаны, владелец должен иметь shell-доступ для диагностики и восстановления.

Build pipeline проверяет `/usr/sbin/dropbear` и init-script Dropbear прямо
в `rootfs.ext2`. Если SSH исчезнет из будущего image, сборка должна упасть.
