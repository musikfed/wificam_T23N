#!/bin/sh
# Hardware execution probe for BusyBox httpd CGI on Ingenic T23/T23N.
# Does NOT replace system BusyBox, launch the public :8090 listener, write
# flash/SD, change SSH credentials, or disable the S90wificam security gate.
# On camera: sh camera_smoke_httpd_cgi.sh [PATH_TO_CANDIDATE_BUSYBOX]
set -eu

CANDIDATE="${1:-/bin/busybox}"
PORT="${WIFICAM_TEST_PORT:-18090}"
case "$PORT" in
    *[!0-9]*|"") echo "ERROR: numeric test port required" >&2; exit 2 ;;
esac
[ "$PORT" -ge 1024 ] && [ "$PORT" -le 65535 ] || {
    echo "ERROR: use a non-privileged test port" >&2
    exit 2
}
[ -f "$CANDIDATE" ] && [ -x "$CANDIDATE" ] || {
    echo "ERROR: candidate BusyBox not executable: $CANDIDATE" >&2
    exit 2
}
command -v curl >/dev/null 2>&1 || {
    echo "ERROR: curl is required for the loopback CGI smoke test" >&2
    exit 2
}
WORK="$(mktemp -d /tmp/wificam-cgi-probe.XXXXXX)" || exit 2
PID=""
cleanup() {
    if [ -n "$PID" ]; then
        kill "$PID" 2>/dev/null || true
        wait "$PID" 2>/dev/null || true
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$WORK/www/cgi-bin"
cat > "$WORK/www/cgi-bin/probe" <<'EOF'
#!/bin/sh
printf 'Content-Type: application/json\r\n\r\n'
printf '{"ok":true,"cgi":"executed"}\n'
EOF
chmod 0700 "$WORK/www/cgi-bin/probe"
: > "$WORK/httpd.conf"
# Bind loopback ONLY; never expose CGI source even temporarily over LAN.
"$CANDIDATE" httpd -f -p "127.0.0.1:$PORT" \
    -h "$WORK/www" -c "$WORK/httpd.conf" >"$WORK/httpd.log" 2>&1 &
PID=$!
sleep 2
if ! kill -0 "$PID" 2>/dev/null; then
    echo "FAIL: candidate httpd exited; output follows:" >&2
    tail -n 15 "$WORK/httpd.log" >&2
    exit 1
fi
CODE="$(curl --silent --show-error --max-time 5 \
    -o "$WORK/response" -w '%{http_code}' \
    "http://127.0.0.1:$PORT/cgi-bin/probe" 2>"$WORK/curl.err")" || {
    echo "FAIL: CGI probe request did not complete" >&2
    cat "$WORK/curl.err" >&2
    exit 1
}
BODY="$(cat "$WORK/response")"
if [ "$CODE" != 200 ] || [ "$BODY" != '{"ok":true,"cgi":"executed"}' ]; then
    echo "FAIL: httpd does not execute CGI (HTTP=$CODE)." >&2
    case "$BODY" in
        '#!'*) echo "SECURITY: CGI SOURCE EXPOSED by candidate; DO NOT bind this binary to :8090!" >&2 ;;
        *) echo "Unexpected response (first 160 bytes):" >&2
           head -c 160 "$WORK/response" >&2
           echo >&2 ;;
    esac
    exit 1
fi
echo "PASS: candidate BusyBox httpd EXECUTED CGI and returned JSON over 127.0.0.1:$PORT"
echo "SAFE: only loopback used; production :8090 was not started or changed"
