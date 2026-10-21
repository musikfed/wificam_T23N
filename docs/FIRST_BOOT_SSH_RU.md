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

Новые сборки содержат отдельную first-boot страницу:

```text
http://CAMERA_IP:8090/
```

Пока пароль администратора не создан, web server обслуживает только setup
страницу, а основная PegineLab админка/API не публикуются без авторизации.

На first-boot странице задаётся пароль не короче 10 символов. Пользователь
фиксирован как:

```text
admin
```

После сохранения WIFICAM перезапускается и браузер запросит HTTP Basic Auth.

Файл авторизации:

```text
/opt/wificam/httpd.conf
```

### Уже записанная 0.1_test карта

Старая карта, записанная до переноса на 8090 и добавления setup-page, может
быть исправлена без пересборки kernel:

```sh
sed -i 's/^WEB_PORT=.*/WEB_PORT=8090/' /etc/wificam/wificam.conf
printf '%s' 'НОВЫЙ_ПАРОЛЬ_НЕ_КОРОЧЕ_10' | wificam-set-web-password admin
/etc/init.d/S90wificam restart
```

После этого:

```text
http://CAMERA_IP:8090/
login: admin
password: заданный пароль
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
