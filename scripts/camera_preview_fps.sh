#!/bin/sh
# Optional camera-local Raptor JPEG FPS tuning. Never disables drivers or SSH.
# The original value is saved for an explicit restore. No automatic restart.
set -eu

STATE_DIR="${STATE_DIR:-/opt/wificam}"
ORIGINAL="$STATE_DIR/raptor-jpeg-fps.before-wificam"
SVC=/etc/init.d/S31raptor

usage() {
    echo "Usage: sh camera_preview_fps.sh show|apply 8..15|restore"
    echo "Fps setting is persisted, but Raptor restart is MANUAL over SSH."
    exit 2
}
[ "$#" -ge 1 ] || usage
command -v raptorctl >/dev/null 2>&1 || { echo "Raptor control CLI is unavailable"; exit 3; }

current() {
    val="$(raptorctl config get jpeg fps 2>/dev/null | tr -d ' \r\n\t')"
    case "$val" in ''|*[!0-9]*) echo 1 ;; *) echo "$val" ;; esac
}
show() {
    printf 'Raptor JPEG FPS: %s\n' "$(current)"
    printf 'Raptor stream0 JPEG FPS override: '
    raptorctl config get stream0 jpeg_fps 2>/dev/null || true
    echo
    printf 'Native HTTP/MJPEG: '
    pidof rhd 2>/dev/null || echo "rhd not running"
    echo "For lower latency: use :8090/cgi-bin/live.mjpg, not repeated snapshot CGI"
}
case "$1" in
 show) show ;;
 apply)
    [ "$#" -eq 2 ] || usage
    fps="$2"
    case "$fps" in ''|*[!0-9]*) usage ;; esac
    [ "$fps" -ge 8 ] && [ "$fps" -le 15 ] || usage
    mkdir -p "$STATE_DIR"
    if [ ! -s "$ORIGINAL" ]; then
        umask 077
        current > "$ORIGINAL"
    fi
    echo "Saving JPEG FPS $fps (previous $(cat "$ORIGINAL"))"
    raptorctl config set jpeg fps "$fps"
    raptorctl config save
    echo "Saved. Restart Raptor manually ONLY after confirming SSH stays open:"
    echo "  $SVC restart"
    echo "Restore: sh /tmp/camera_preview_fps.sh restore"
    ;;
 restore)
    [ -s "$ORIGINAL" ] || { echo "No saved FPS baseline, refusing guess"; exit 3; }
    fps="$(cat "$ORIGINAL")"
    case "$fps" in ''|*[!0-9]*) echo "Invalid saved value" >&2; exit 4 ;; esac
    raptorctl config set jpeg fps "$fps"
    raptorctl config save
    echo "Restored configured FPS $fps. Restart Raptor manually when ready."
    ;;
 *) usage ;;
esac
