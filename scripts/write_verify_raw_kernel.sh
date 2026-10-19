#!/bin/sh
set -eu

DEV="${1:-}"
IMAGE="${2:-}"
CONFIRM="${3:-}"

KERNEL_SECTOR=$((0x1800))
KERNEL_SLOT_SECTORS=$((0x3000))

die() { echo "ERROR: $*" >&2; exit 1; }

[ -n "$DEV" ] && [ -n "$IMAGE" ] || {
    echo "Usage: sudo $0 /dev/sdX uImage [--yes]" >&2
    exit 2
}
[ "$(id -u)" -eq 0 ] || die "run with sudo/root"
[ -b "$DEV" ] || die "not a block device: $DEV"
[ -f "$IMAGE" ] || die "kernel image not found: $IMAGE"
command -v readlink >/dev/null 2>&1 || die "readlink is required"
IMAGE_REAL="$(readlink -f "$IMAGE")"
[ -f "$IMAGE_REAL" ] || die "resolved kernel image not found: $IMAGE_REAL"
[ "$(lsblk -dn -o TYPE "$DEV" 2>/dev/null)" = "disk" ] || die "$DEV is not a whole disk"

case "$DEV" in
  /dev/sd[a-z]|/dev/mmcblk[0-9]) ;;
  *) die "refusing suspicious device name: $DEV" ;;
esac

SECTOR_SIZE="$(blockdev --getss "$DEV")"
[ "$SECTOR_SIZE" -eq 512 ] || die "expected 512-byte sectors, got $SECTOR_SIZE"

# Resolve uImage once and measure the real file through an opened file
# descriptor. This avoids stat/symlink ambiguity completely.
KERNEL_SIZE="$(wc -c < "$IMAGE_REAL" | tr -d ' ')"
KERNEL_SLOT_BYTES=$((KERNEL_SLOT_SECTORS * 512))
[ "$KERNEL_SIZE" -le "$KERNEL_SLOT_BYTES" ] || die "kernel is larger than the 6 MiB raw slot"
KERNEL_BLOCKS=$(((KERNEL_SIZE + 511) / 512))

if [ "$CONFIRM" != "--yes" ]; then
    echo "Target: $DEV"
    lsblk -o NAME,PATH,SIZE,LABEL,FSTYPE,MODEL,TRAN,RM,MOUNTPOINTS "$DEV"
    printf "Type RAW-KERNEL:%s to rewrite only the redundant raw kernel backup at sector 0x1800: " "$DEV"
    read answer
    [ "$answer" = "RAW-KERNEL:$DEV" ] || { echo "Cancelled."; exit 1; }
fi

PAD="$(mktemp)"
READ1="$(mktemp)"
READ2="$(mktemp)"
cleanup() {
    rm -f "$PAD" "$READ1" "$READ2"
}
trap cleanup EXIT INT TERM

cp "$IMAGE_REAL" "$PAD"
truncate -s $((KERNEL_BLOCKS * 512)) "$PAD"

SOURCE_SHA="$(sha256sum "$IMAGE_REAL" | awk '{print $1}')"
PAD_SOURCE_SHA="$(head -c "$KERNEL_SIZE" "$PAD" | sha256sum | awk '{print $1}')"
[ "$SOURCE_SHA" = "$PAD_SOURCE_SHA" ] || die "internal staging copy SHA mismatch"

echo "Kernel requested path : $IMAGE"
echo "Kernel resolved path  : $IMAGE_REAL"
echo "Kernel bytes          : $KERNEL_SIZE"
echo "Kernel sectors        : $KERNEL_BLOCKS"

echo "Writing redundant raw uImage backup at sector 0x1800 ..."
dd if=/dev/zero of="$DEV" bs=512 seek="$KERNEL_SECTOR" count="$KERNEL_SLOT_SECTORS" conv=notrunc status=none

if ! dd if="$PAD" of="$DEV" bs=512 seek="$KERNEL_SECTOR" count="$KERNEL_BLOCKS" oflag=direct conv=notrunc,fsync status=none 2>/dev/null; then
    echo "Direct write is unavailable; retrying with normal I/O."
    dd if="$PAD" of="$DEV" bs=512 seek="$KERNEL_SECTOR" count="$KERNEL_BLOCKS" conv=notrunc,fsync status=none
fi

sync
blockdev --flushbufs "$DEV" 2>/dev/null || true
sleep 2

read_back() {
    OUT="$1"
    if ! dd if="$DEV" of="$OUT" bs=512 skip="$KERNEL_SECTOR" count="$KERNEL_BLOCKS" iflag=direct status=none 2>/dev/null; then
        dd if="$DEV" of="$OUT" bs=512 skip="$KERNEL_SECTOR" count="$KERNEL_BLOCKS" status=none
    fi
}

read_back "$READ1"
READ1_SHA="$(head -c "$KERNEL_SIZE" "$READ1" | sha256sum | awk '{print $1}')"

echo "Kernel source SHA256 : $SOURCE_SHA"
echo "Kernel SD SHA256     : $READ1_SHA"

# Never report OK unless the full, unpadded kernel SHA also matches.
if [ "$SOURCE_SHA" = "$READ1_SHA" ] && cmp -s "$PAD" "$READ1"; then
    echo "Raw kernel backup readback : OK"
    exit 0
fi

echo "First raw readback differs; flushing and reading a second time..." >&2
sync
blockdev --flushbufs "$DEV" 2>/dev/null || true
sleep 2
read_back "$READ2"
READ2_SHA="$(head -c "$KERNEL_SIZE" "$READ2" | sha256sum | awk '{print $1}')"

echo "Kernel source SHA256 : $SOURCE_SHA"
echo "Kernel SD read #1    : $READ1_SHA"
echo "Kernel SD read #2    : $READ2_SHA"

FIRST_DIFF="$(cmp -l "$PAD" "$READ1" 2>/dev/null | head -n 1 || true)"
[ -n "$FIRST_DIFF" ] && echo "First differing byte : $FIRST_DIFF"

if cmp -s "$READ1" "$READ2"; then
    die "raw kernel backup write/read is repeatable but differs from source"
else
    die "raw kernel backup reads are unstable; check SD card / reader / usbipd path"
fi
