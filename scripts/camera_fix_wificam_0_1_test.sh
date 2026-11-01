#!/bin/sh
set -eu

# Recover the first hardware-booted 0.1_test image without rebuilding kernel/rootfs.
# Run ON THE CAMERA as root (SSH). Safe defaults match the hardware-verified setup.

WEB_PORT="${WEB_PORT:-8090}"
WEB_USER="${WEB_USER:-admin}"
WEB_PASSWORD="${WEB_PASSWORD:-Wificam12345}"
WEBROOT="${WEBROOT:-/usr/share/wificam-web}"
AUTH_CONF="${AUTH_CONF:-/opt/wificam/httpd.conf}"
CONF="${CONF:-/etc/wificam/wificam.conf}"
CSRF_FILE="${CSRF_FILE:-/var/run/wificam-csrf}"

[ "$(id -u)" = "0" ] || { echo "ERROR: run as root on the camera" >&2; exit 1; }
[ -f "$WEBROOT/index.html" ] || { echo "ERROR: PegineLab webroot missing: $WEBROOT" >&2; exit 1; }
command -v httpd >/dev/null 2>&1 || command -v busybox >/dev/null 2>&1 || {
    echo "ERROR: BusyBox httpd unavailable" >&2
    exit 1
}

echo "[1/6] Set WIFICAM port to $WEB_PORT"
if grep -q '^WEB_PORT=' "$CONF" 2>/dev/null; then
    sed -i "s/^WEB_PORT=.*/WEB_PORT=$WEB_PORT/" "$CONF"
else
    printf '\nWEB_PORT=%s\n' "$WEB_PORT" >> "$CONF"
fi

echo "[2/6] Write verified standalone BusyBox httpd config"
mkdir -p "$(dirname "$AUTH_CONF")"
umask 077
cat > "$AUTH_CONF" <<EOF
H:$WEBROOT
/:$WEB_USER:$WEB_PASSWORD
EOF
chmod 600 "$AUTH_CONF"

echo "[3/6] Seed CSRF without GNU od options"
mkdir -p "$(dirname "$CSRF_FILE")"
if [ -r /dev/urandom ] && command -v sha256sum >/dev/null 2>&1; then
    dd if=/dev/urandom bs=32 count=1 2>/dev/null | sha256sum | awk '{print $1}' > "$CSRF_FILE"
else
    printf '%s-%s\n' "$(date +%s 2>/dev/null || echo 0)" "$$" > "$CSRF_FILE"
fi
chmod 600 "$CSRF_FILE"

echo "[4/6] Stop only PegineLab httpd on $WEB_PORT"
if [ -x /etc/init.d/S90wificam ]; then
    /etc/init.d/S90wificam stop 2>/dev/null || true
fi
PID="$(ps w 2>/dev/null | awk -v p="$WEB_PORT" '$0 ~ /[h]ttpd/ && $0 ~ ("-p " p "([[:space:]]|$)") {print $1; exit}')"
[ -z "$PID" ] || kill "$PID" 2>/dev/null || true
sleep 1

echo "[5/6] Start PegineLab WIFICAM"
if [ -x /etc/init.d/S90wificam ]; then
    /etc/init.d/S90wificam start
else
    /usr/sbin/httpd -f -p "$WEB_PORT" -c "$AUTH_CONF" -r "PegineLab WIFICAM T23N" \
        >/var/log/wificam-httpd.log 2>&1 &
fi
sleep 2

echo "[6/6] Verify"
netstat -lntp 2>/dev/null | grep ":$WEB_PORT" || true
if command -v curl >/dev/null 2>&1; then
    code="$(curl -s -o /tmp/wificam-check.html -w '%{http_code}' -u "$WEB_USER:$WEB_PASSWORD" "http://127.0.0.1:$WEB_PORT/" || true)"
    echo "HTTP status: $code"
    grep -m1 -E 'PegineLab|WIFICAM' /tmp/wificam-check.html 2>/dev/null || true
    [ "$code" = "200" ] || {
        echo "ERROR: WIFICAM verification failed; see /var/log/wificam-httpd.log" >&2
        exit 1
    }
fi

echo
echo "PegineLab WIFICAM recovered:"
echo "  URL      : http://CAMERA_IP:$WEB_PORT/"
echo "  login    : $WEB_USER"
echo "  password : $WEB_PASSWORD"
echo "SSH/Dropbear was not stopped or modified."
