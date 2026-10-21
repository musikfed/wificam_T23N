# PegineLab WIFICAM — first boot, authentication and SSH

## Web endpoints

```text
Thingino stock UI : http://CAMERA_IP/ or https://CAMERA_IP/
Thingino login    : root
Thingino password : root

Thingino camera/API backend : TCP 8080
PegineLab WIFICAM           : http://CAMERA_IP:8090/
```

TCP 8080 belongs to Thingino's camera/API stack. PegineLab uses TCP 8090.

## First-boot authentication

New builds serve a dedicated setup page at:

```text
http://CAMERA_IP:8090/
```

Until an admin password exists, only the setup webroot is served. The main
dashboard/API are not exposed unauthenticated.

The fixed PegineLab username is `admin`; password length is at least 10
characters. After saving, WIFICAM restarts with HTTP Basic Auth.

Authentication state is stored in `/opt/wificam/httpd.conf`.

### Already-flashed 0.1_test card

Fix an older card without rebuilding the kernel:

```sh
sed -i 's/^WEB_PORT=.*/WEB_PORT=8090/' /etc/wificam/wificam.conf
printf '%s' 'NEW_PASSWORD_AT_LEAST_10' | wificam-set-web-password admin
/etc/init.d/S90wificam restart
```

Then open `http://CAMERA_IP:8090/` and log in as `admin`.

## SSH from Windows PowerShell

```powershell
ssh root@192.168.1.55
```

Default password: `root`.

After an expected reflash, if OpenSSH reports
`REMOTE HOST IDENTIFICATION HAS CHANGED`:

```powershell
ssh-keygen -R 192.168.1.55
ssh root@192.168.1.55
```

Only replace the stored key when the change is expected and the IP is known to
belong to the intended camera.

## SSH from Linux / Ubuntu / WSL

```sh
ssh-keygen -R 192.168.1.55   # only after an expected reflash/key change
ssh root@192.168.1.55
```

Default password: `root`.

Thingino uses Dropbear. If SCP fails due to SFTP mode:

```sh
scp -O file root@192.168.1.55:/tmp/
```

## Change WIFICAM port without rebuilding the kernel

```sh
grep '^WEB_PORT=' /etc/wificam/wificam.conf
sed -i 's/^WEB_PORT=.*/WEB_PORT=8090/' /etc/wificam/wificam.conf
/etc/init.d/S90wificam restart
sleep 2
netstat -lnt 2>/dev/null | grep ':8090'
cat /var/log/wificam-httpd.log
```

This is a userspace-only change.

## Common errors

- Raptor on 8080: expected; PegineLab is on 8090.
- Connection refused on 8090: inspect WEB_PORT, listeners and
  `/var/log/wificam-httpd.log`.
- Read-only filesystem: `mount -o remount,rw /`.
- PegineLab Basic Auth: use `admin` plus the configured PegineLab password.
- SSH default: `root/root`, unless changed.
- Host identification changed: remove stale known_hosts entry only after an
  expected reflash/key change.
