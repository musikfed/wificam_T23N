#!/bin/sh
# Hardware-free PTZ tests: simulate motors and ensure reverse axes are safe.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/state"
cat > "$TMP/bin/pidof" <<'EOF'
#!/bin/sh
[ "$1" = motors-daemon ]
EOF
cat > "$TMP/bin/motors" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$MOTOR_LOG"
EOF
chmod +x "$TMP/bin/pidof" "$TMP/bin/motors"
export MOTOR_LOG="$TMP/motor.log"
export PATH="$TMP/bin:$PATH"
export STATE_DIR="$TMP/state"
export PTZ_STEP=50
PTZ="$ROOT/rootfs/usr/bin/wificam-ptz-ctl"
status="$(sh "$PTZ" status)"
printf '%s' "$status" | grep -q '"ptz":true'
sh "$PTZ" move left
sh "$PTZ" move up
sh "$PTZ" invert pan 1 >/dev/null
sh "$PTZ" move left
sh "$PTZ" invert tilt 1 >/dev/null
sh "$PTZ" move up
[ "$(sed -n '1p' "$MOTOR_LOG")" = '-d g -x -50' ]
[ "$(sed -n '2p' "$MOTOR_LOG")" = '-d g -y -50' ]
[ "$(sed -n '3p' "$MOTOR_LOG")" = '-d g -x 50' ]
[ "$(sed -n '4p' "$MOTOR_LOG")" = '-d g -y 50' ]
grep -q '^PAN_INVERT=1$' "$TMP/state/ptz-controls.conf"
grep -q '^TILT_INVERT=1$' "$TMP/state/ptz-controls.conf"
if sh "$PTZ" move '../../../../bin/sh' >/dev/null 2>&1; then
  echo "unsafe direction accepted" >&2; exit 1
fi
if sh "$PTZ" invert pan '0;id' >/dev/null 2>&1; then
  echo "unsafe inversion accepted" >&2; exit 1
fi
echo "PTZ simulator: OK, bounded steps and both reverse axes verified"
