#!/bin/sh
# Incremental CGI-capable BusyBox candidate for the pinned Thingino T23N job.
# Must be invoked from the EXISTING successful job checkout on Huananzhi.
# Does not rebuild the kernel, overwrite the SD image, install anything on
# the camera, replace /bin/busybox, or restart any systemd/SSH services.
set -eu
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
THINGINO_DIR="${THINGINO_DIR:-/1tbdisk/PegineLab/build/thingino-firmware}"
CAMERA="${CAMERA:-galayou_g2_t23n_sc2336_atbm6012bx}"
USER_ROOT="$REPO_DIR/out/thingino-user"
FRAGMENT="$USER_ROOT/$CAMERA/busybox-wificam.fragment"
OUT="$REPO_DIR/out/candidate-busybox"
die() { echo "ERROR: $*" >&2; exit 1; }

[ -f "$FRAGMENT" ] || die "Missing old job build configuration: $FRAGMENT. Use the original build/jobs/<ID>/wificam_T23N checkout."
[ -d "$THINGINO_DIR/.git" ] || die "Thingino checkout missing: $THINGINO_DIR"
[ -f "$THINGINO_DIR/Makefile" ] || die "Thingino Makefile not found"
for opt in CONFIG_HTTPD=y CONFIG_FEATURE_HTTPD_CGI=y CONFIG_FEATURE_HTTPD_BASIC_AUTH=y; do
    grep -Fxq "$opt" "$FRAGMENT" || die "Required option missing from BusyBox fragment: $opt"
done
grep -Fxq '# CONFIG_FEATURE_FORCE_APPLETS is not set' "$FRAGMENT" || \
    die "Fragment must explicitly disable FEATURE_FORCE_APPLETS"

# Never modify Thingino's shared build directory while factory jobs run.
FACTORY_DB=/1tbdisk/PegineLab/factory-state/factory.sqlite3
if [ -f "$FACTORY_DB" ]; then
    python3 - "$FACTORY_DB" <<'PY'
import sqlite3, sys
try:
    with sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True, timeout=3) as db:
        row = db.execute("SELECT 1 FROM jobs WHERE status IN ('queued','running','stopping') LIMIT 1").fetchone()
        if row:
            raise SystemExit("ERROR: YadroKreator has a build job running; aborting BusyBox-only rebuild")
except sqlite3.DatabaseError as e:
    raise SystemExit(f"ERROR: unable to inspect factory job state: {e}")
PY
fi

echo "=== Isolated incremental BusyBox build (NOT a kernel/full SD build) ==="
echo "Worktree: $REPO_DIR"
echo "Thingino: $THINGINO_DIR"
echo "Camera:   $CAMERA"
(
    cd "$THINGINO_DIR"
    env IP= THINGINO_USER_DIR="$USER_ROOT" \
        make CAMERA="$CAMERA" br-busybox-reconfigure
    env IP= THINGINO_USER_DIR="$USER_ROOT" \
        make CAMERA="$CAMERA" br-busybox-rebuild
)

# Look for the same camera output tree used by the successful SD build.
SPI="$(find "$THINGINO_DIR/output" -type f \
    -path "*/images/thingino-$CAMERA.bin" -printf '%T@ %p\n' \
    | sort -n | tail -n1 | cut -d' ' -f2-)"
[ -n "$SPI" ] && [ -f "$SPI" ] || die "Camera Buildroot output was not found"
OUTDIR="$(dirname "$(dirname "$SPI")")"
BUSYBOX_CFG="$(find "$OUTDIR/build" -type f -path '*/busybox-*/.config' | head -n1)"
[ -f "$BUSYBOX_CFG" ] || die "No BusyBox configuration after incremental rebuild"
for opt in CONFIG_HTTPD=y CONFIG_FEATURE_HTTPD_CGI=y CONFIG_FEATURE_HTTPD_BASIC_AUTH=y; do
    grep -Fxq "$opt" "$BUSYBOX_CFG" || die "Rebuilt config missing $opt"
done
if grep -Fxq CONFIG_FEATURE_FORCE_APPLETS=y "$BUSYBOX_CFG"; then
    die "BusyBox has FORCE_APPLETS=y, which prevents CGI exec"
fi

# Buildroot may install /bin/busybox or /usr/bin/busybox. Use actual target
# binary, dereferencing its symlink, not the host Ubuntu busybox executable.
TARGET="$OUTDIR/target"
if [ -f "$TARGET/usr/bin/busybox" ]; then
    BINARY="$TARGET/usr/bin/busybox"
elif [ -f "$TARGET/bin/busybox" ]; then
    BINARY="$TARGET/bin/busybox"
else
    die "No rebuilt target BusyBox in $TARGET"
fi
mkdir -p "$OUT"
cp -L "$BINARY" "$OUT/busybox-cgi-candidate"
chmod 0755 "$OUT/busybox-cgi-candidate"
sha256sum "$OUT/busybox-cgi-candidate" > "$OUT/busybox-cgi-candidate.sha256"
echo
echo "Candidate file: $OUT/busybox-cgi-candidate"
echo "Important: .config is not proof of CGI execution."
echo "Next: copy this *candidate*, not /bin/busybox, to the camera's /tmp"
echo "Then run scripts/camera_smoke_httpd_cgi.sh on CAMERA loopback."
echo "Only a real PASS makes it eligible for the private WIFICAM listener."
