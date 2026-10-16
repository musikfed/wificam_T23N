#!/bin/sh
set -eu

HERE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BASE="${1:-}"
OUT_TAR="${2:-$HERE/out/wificam-rootfs.tar.gz}"

[ -n "$BASE" ] || {
  echo "Usage: $0 BASE_ROOTFS.tar.gz [OUTPUT.tar.gz]" >&2
  exit 2
}
[ -f "$BASE" ] || { echo "Base rootfs not found: $BASE" >&2; exit 1; }

sh "$HERE/scripts/package_rootfs_overlay.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

tar -C "$WORK" -xzf "$BASE"
tar -C "$WORK" -xzf "$HERE/out/wificam-rootfs-overlay.tar.gz"

mkdir -p "$HERE/out"
tar -C "$WORK" -czf "$OUT_TAR" .

echo "Full rootfs created: $OUT_TAR"
echo "NOTE: the base rootfs must already contain BusyBox/Linux userspace and the required network tools."
