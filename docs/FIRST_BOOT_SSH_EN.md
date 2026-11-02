## 0.1_test default login

The current hardware-test branch uses known LAN-only PegineLab credentials:

```text
URL:      http://CAMERA_IP:8090/
login:    admin
password: Wificam12345
```

This is intentionally **not production security**. It avoids the MD5-crypt
compatibility problem observed on the pinned BusyBox/uClibc hardware image and
makes Web UI access deterministic during hardware bring-up.

The build uses `AUTO_PROVISION_TEST_WEB_AUTH=1` and plaintext BusyBox
httpd.conf compatibility mode. Disable auto-provision for production to use
the first-boot claim page.

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

The `0.1_test` branch temporarily uses deterministic LAN-only credentials:

```text
http://CAMERA_IP:8090/
login: admin
password: Wificam12345
```

The production first-boot claim flow remains in source and can be enabled by
disabling test auto-provision.

Authentication state is stored in `/opt/wificam/httpd.conf`.

### Already-flashed 0.1_test card

Fix an older card without rebuilding the kernel:

```sh
sed -i 's/^WEB_PORT=.*/WEB_PORT=8090/' /etc/wificam/wificam.conf
printf '%s' 'NEW_PASSWORD_AT_LEAST_10' | wificam-set-web-password admin
/etc/init.d/S90wificam restart
```

Then open `http://CAMERA_IP:8090/` and log in as `admin`.

## Observed first Thingino SSH login (2026-11-02)

On the actual T23N camera the SSH banner appeared after the Wi-Fi
connection at `192.168.1.55`. Thingino immediately printed:

```text
It's your first login.
You are required to change your password!
Password:
```

The SSH authentication prompt `root@192.168.1.55's password:` initially
accepts the default `root` on an unchanged test image. **The subsequent
`Password:` prompt is for a NEW root password**, not the old one!
It then asks `Confirm:`; both entries must match, and Thingino's
[chpasswd profile](https://github.com/themactep/thingino-firmware/blob/24ec28c7457686ff733132e580267d6a95308c80/overlay/etc/profile.d/chpasswd)
rejects `root` or an empty string. Subsequent SSH and Thingino Web logins
must use the new password. PegineLab's separate `admin / Wificam12345`
account is still test-only.

See the [real-camera first-boot walkthrough](REAL_CAMERA_FIRST_BOOT_EN.md)
for read-only MMC-root and independent PegineLab :8090 diagnostics.
Wi-Fi + SSH do not yet prove video, PTZ or SD-root boot.

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


## Thingino/Raptor still appears on port 8090

This was diagnosed on the first hardware `0.1_test`. The old bootstrap
started BusyBox `httpd` without `-c`, so BusyBox loaded Thingino's
`/etc/httpd.conf`. Its `H:/var/www` directive overrides PegineLab's
`-h /usr/share/wificam-web`, making the PegineLab process serve Thingino.

Current code always passes a private bootstrap config and never reads
Thingino's `/etc/httpd.conf`.

For an already-flashed old card, create PegineLab authentication first:

```sh
grep -m1 -E 'PegineLab|WIFICAM' /usr/share/wificam-web/index.html
printf '%s' 'NEW_PASSWORD_AT_LEAST_10' | wificam-set-web-password admin
/etc/init.d/S90wificam stop 2>/dev/null || true
killall httpd 2>/dev/null || true
/etc/init.d/S90httpd start
/etc/init.d/S90wificam start
sleep 2
curl -s http://127.0.0.1:8090/ | head -n 12
```

Open `http://CAMERA_IP:8090/`, not Thingino's `/preview.html`.

The BusyBox `od: invalid option -- A` issue is also fixed: current CSRF
generation uses `dd /dev/urandom | sha256sum` and does not require GNU od.


## SSH is a mandatory local recovery channel

For `0.1_test`, Dropbear on TCP 22 is part of the acceptance criteria.
`SSH_PROTECT=1` prevents PegineLab from accidentally disabling SSH. The build
also verifies the Dropbear binary and init script inside `rootfs.ext2`.

This is intentional for local/cloudless ownership: the owner keeps shell
access even when the Web UI or camera services need recovery.
