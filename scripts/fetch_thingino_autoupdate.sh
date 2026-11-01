#!/bin/sh
set -eu

ASSET="${1:-}"
OUTDIR="${2:-out}"

die() { echo "ERROR: $*" >&2; exit 1; }

[ -n "$ASSET" ] || {
    echo "Usage: $0 thingino-EXACT_CAMERA_PROFILE.bin [outdir]" >&2
    echo "Example asset name:" >&2
    echo "  thingino-jooan_q3r_t23n_sc1a4t_eth+atbm6012bx.bin" >&2
    echo >&2
    echo "This helper does NOT guess the camera profile." >&2
    exit 2
}

case "$ASSET" in
  thingino-*.bin) ;;
  *) die "asset must be an exact Thingino release filename: thingino-*.bin" ;;
esac

command -v curl >/dev/null 2>&1 || die "curl not installed"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum not installed"
command -v wc >/dev/null 2>&1 || die "wc not installed"

mkdir -p "$OUTDIR"
TMP="$OUTDIR/autoupdate-full.bin.tmp"
DST="$OUTDIR/autoupdate-full.bin"
URL="https://github.com/themactep/thingino-firmware/releases/latest/download/$ASSET"

echo "Thingino source asset:"
echo "  $ASSET"
echo
echo "IMPORTANT: this helper does not verify that the profile matches your camera."
echo "The sensor/Wi-Fi/board profile must be confirmed before using the file."
echo
echo "Downloading:"
echo "  $URL"

rm -f "$TMP"
curl -fL --retry 3 --connect-timeout 20 -o "$TMP" "$URL"

SIZE="$(wc -c < "$TMP" | tr -d ' ')"
[ "$SIZE" -gt 0 ] || {
    rm -f "$TMP"
    die "downloaded file is empty"
}

mv "$TMP" "$DST"

echo
echo "THINGINO AUTOUPDATE PAYLOAD READY"
echo "Source asset : $ASSET"
echo "Saved as     : $DST"
echo "Size         : $SIZE bytes"
echo "SHA256       : $(sha256sum "$DST" | awk '{print $1}')"
echo
echo "Next, only after confirming the asset is the exact camera profile:"
echo "  sudo sh scripts/prepare_legacy_thingino_sd.sh /dev/YOUR_SD $DST"
