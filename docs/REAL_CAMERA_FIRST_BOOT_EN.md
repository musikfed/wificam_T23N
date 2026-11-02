# Real T23N SD camera first boot — 2026-11-02 (EN)

This is the actual first-SSH-login sequence observed on the test
\`galayou_g2_t23n_sc2336_atbm6012bx\` camera. Router DHCP showed
\`wificam\` at \`192.168.1.55\`; Thingino displayed its SSH banner and
forced the \`root\` password change. This confirms Wi-Fi and SSH, **not yet**
MMC root filesystem, PegineLab Web UI, sensor video, RTSP or PTZ.

## Test-only defaults (not production credentials)

| Service | URL / command | User | Factory/test password |
| --- | --- | --- | --- |
| Thingino Dropbear SSH | \`ssh root@192.168.1.55\` | \`root\` | \`root\` **until changed** |
| Thingino stock Web UI | \`http://192.168.1.55/\` / HTTPS | \`root\` | \`root\` **until changed** |
| PegineLab WIFICAM | **\`http://192.168.1.55:8090/\`** | \`admin\` | \`Wificam12345\` (test only) |
| Thingino camera/API | port \`8080\` | separate service | not PegineLab UI |

IP may differ on other networks; find it in the router's DHCP client list.
\`8090\` uses **HTTP**, not stock Thingino HTTPS.

## Exact Windows PowerShell / Linux SSH sequence

\`\`\`sh
ssh root@192.168.1.55
\`\`\`

The first-time host key confirmation is normal only if you verified the
camera's IP/MAC. Use \`yes\` when the key really belongs to your camera.

At \`root@192.168.1.55's password:\`, enter **the current root password**
(\`root\` on an untouched test image). Input is not echoed.

After the Thingino banner the upstream profile script prompts:

\`\`\`text
It's your first login.
You are required to change your password!

Password:   <-- ENTER A NEW ROOT PASSWORD; NOT THE OLD ONE
Confirm:    <-- ENTER THE SAME NEW PASSWORD
Password updated.
\`\`\`

Source: [Thingino \`overlay/etc/profile.d/chpasswd\`](https://github.com/themactep/thingino-firmware/blob/24ec28c7457686ff733132e580267d6a95308c80/overlay/etc/profile.d/chpasswd).
It rejects empty passwords and \`root\` itself, checks that both entries
match, and updates \`root\` with \`chpasswd\`. It does **not** ask for the
old password a second time. After changing the password, future SSH access
must use the new password, while PegineLab \`admin\` remains a distinct
account. Do not commit or share the new password.

The stock Thingino web path \`/config-webui.html?force_password_change=1\`
likewise belongs to Thingino, **not** PegineLab.

## Read-only checks after the forced password change

\`\`\`sh
cat /proc/cmdline
cat /proc/mounts | grep mmcblk
ls -l /usr/share/wificam-web/index.html
grep '^WEB_PORT=' /etc/wificam/wificam.conf
netstat -lnt 2>/dev/null | grep -E ':80 |:443 |:8080 |:8090 '
ps | grep '[h]ttpd'
tail -n 40 /var/log/wificam-httpd.log 2>/dev/null
\`\`\`

Confirm the SD root filesystem via \`root=/dev/mmcblk0p2\` or an ext4
root mounted from \`/dev/mmcblk0p2\`. Seeing the Thingino banner and Wi-Fi
alone is not enough to prove this.

If \`:8090\` does not show PegineLab, inspect the results *before*
restarting services or writing a new SD. See
[FIRST_BOOT_SSH_EN.md](FIRST_BOOT_SSH_EN.md) for the userspace-only
BusyBox \`httpd\` troubleshooting. Do not rebuild the kernel yet.

**Next acceptance gates:** MMC root, independent PegineLab UI on port
8090, Thingino camera/Prudynt preview, RTSP, PTZ, audio and reboot.
Wi-Fi + SSH are the only items shown by the current camera screenshot.

**Security:** replace all factory/test passwords and rotate an exposed
Thingino API key. Never paste Wi-Fi credentials or private keys into logs
or screenshots. Rewriting the SD image may restore the original first-login
credentials and require changing them again.
