#!/bin/sh
# Simulated CGI contract for PTZ, no camera required.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin"
cat > "$TMP/bin/wificam-ptz-ctl" <<'EOF'
#!/bin/sh
case "$1" in
 status) echo '{"ok":true,"ptz":true,"pan_invert":false,"tilt_invert":false,"autofocus":false}' ;;
 move) [ "$2" = left ] && echo 'moved' ;;
 invert) echo '{"ok":true,"ptz":true}' ;;
 *) exit 2 ;;
esac
EOF
chmod +x "$TMP/bin/wificam-ptz-ctl"
export PATH="$TMP/bin:$PATH"
API="$ROOT/web/cgi-bin/api"
QUERY_STRING='op=ptz_status' REQUEST_METHOD=GET sh "$API" > "$TMP/status"
grep -q '^Content-Type: application/json' "$TMP/status"
grep -q '"ptz":true' "$TMP/status"
QUERY_STRING='op=ptz_move' REQUEST_METHOD=POST sh "$API" <<<'direction=left' > "$TMP/no-auth"
grep -q 'web authentication required' "$TMP/no-auth"
printf 'token42\n' > "$TMP/csrf"
printf '%s\n' 'direction=left&csrf=token42' |
  CSRF_FILE="$TMP/csrf" REMOTE_USER=admin QUERY_STRING='op=ptz_move' REQUEST_METHOD=POST sh "$API" > "$TMP/moved"
grep -q '"ok":true' "$TMP/moved"
printf '%s\n' 'direction=../../tmp&csrf=token42' |
  CSRF_FILE="$TMP/csrf" REMOTE_USER=admin QUERY_STRING='op=ptz_move' REQUEST_METHOD=POST sh "$API" > "$TMP/rejected"
grep -q 'invalid PTZ direction' "$TMP/rejected"
echo "PTZ CGI: JSON headers/auth/CSRF/input checks passed"
