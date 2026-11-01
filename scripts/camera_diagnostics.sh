#!/bin/sh
set -u

# Run on the T23N camera as root over SSH. Read-only diagnostics.
CONF=/etc/wificam/wificam.conf
[ -f "$CONF" ] && . "$CONF"
WEB_PORT="${WEB_PORT:-8090}"
WEB_USER="${WEB_USER:-admin}"
# Set WEB_PASSWORD via environment; do not store it in logs.
WEB_PASSWORD="${WEB_PASSWORD:-}"
LOG=/var/log/wificam-httpd.log
TMP=/tmp/wificam-api-probe.$$
trap 'rm -f "$TMP"' EXIT HUP INT TERM

echo "PegineLab WIFICAM diagnostics (read-only)"
echo "Kernel: $(uname -r)"
echo "Web port: $WEB_PORT"
echo "=== Web server and camera processes ==="
ps w 2>/dev/null | grep -E '[h]ttpd|[r]vd|[r]sd|[r]ad|[d]ropbear' || true
echo "=== Listening ports ==="
netstat -lnt 2>/dev/null | grep -E ':22 |:80 |:554 |:8080 |:8090 ' || true
echo "=== CGI files ==="
ls -l /usr/share/wificam-web/cgi-bin/api /usr/share/wificam-web/cgi-bin/snapshot.jpg 2>/dev/null || true
echo "=== BusyBox help ==="
httpd -h 2>&1 | head -n 4 || true

if command -v curl >/dev/null 2>&1 && [ -n "$WEB_PASSWORD" ]; then
    echo "=== API (authenticated) ==="
    code="$(curl --silent --show-error --max-time 8 -u "$WEB_USER:$WEB_PASSWORD" \
        -o "$TMP" -w '%{http_code}' "http://127.0.0.1:$WEB_PORT/cgi-bin/api?op=status" 2>/dev/null || true)"
    echo "HTTP $code"
    case "$(head -c 2 "$TMP" 2>/dev/null)" in
      '#!') echo "FAIL: CGI source served as text (BusyBox CGI not executing)" ;;
      '<H'|'<!') echo "FAIL: HTML returned instead of JSON (check auth/CGI)" ;;
      '{"') echo "Body begins with JSON; validate fields on the host" ;;
      *) echo "Non-JSON response; first 80 bytes (sanitize before sharing):"; head -c 80 "$TMP" 2>/dev/null; echo ;;
    esac
else
    echo "API probe skipped: set WEB_PASSWORD=... and ensure curl is installed"
fi
echo "=== Performance (read-only; do not unload motor/ISP drivers) ==="
printf 'System load: '; cat /proc/loadavg 2>/dev/null || true
printf 'Free memory: '; free 2>/dev/null | head -n 3 || true
printf 'Raptor JPEG fps: '; raptorctl config get jpeg fps 2>/dev/null || echo "Raptor not available"
printf 'Stream0 FPS: '; raptorctl config get stream0 fps 2>/dev/null || echo "n/a"
printf 'Sensor low latency: '; raptorctl config get sensor low_latency 2>/dev/null || echo "n/a"
printf 'Motor daemon: '; pidof motors-daemon 2>/dev/null || echo "not running"
printf 'RHD / RSD / RVD / RAD: '; pidof rhd rsd rvd rad 2>/dev/null || true
echo "=== Recent httpd log ==="
tail -n 15 "$LOG" 2>/dev/null || true
echo "Done. No services were restarted or disabled."
