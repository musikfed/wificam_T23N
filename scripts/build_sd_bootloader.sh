#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$HOME/myipcam}"
UBOOT_SRC="${UBOOT_SRC:-$PROJECT_ROOT/vendor/u-boot-ingenic-t23sd}"
TOOLCHAIN_DIR="${UBOOT_TOOLCHAIN_DIR:-$PROJECT_ROOT/toolchain/mips-gcc472-glibc216-64bit}"
OUT="${UBOOT_SD_OUT:-$REPO_DIR/out/u-boot-t23n-sd.bin}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"

UBOOT_REPO="https://github.com/OpenIPC/u-boot-ingenic.git"
UBOOT_COMMIT="6a308091ef41fd0ba06ba0c668fe406a19210eef"
TOOLCHAIN_REPO="https://github.com/Dafang-Hacks/mips-gcc472-glibc216-64bit.git"
TOOLCHAIN_COMMIT="81cb9f1e63d1abebf8a9a51efb95b6b3a78d9924"
PATCH="$REPO_DIR/patches/u-boot-ingenic-t23n-sd.patch"

die() { echo "ERROR: $*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git not installed"
command -v make >/dev/null 2>&1 || die "make not installed"
command -v gcc >/dev/null 2>&1 || die "host gcc not installed"
[ -f "$PATCH" ] || die "missing patch: $PATCH"

clone_or_pin() {
    url="$1"
    commit="$2"
    dir="$3"

    if [ ! -d "$dir/.git" ]; then
        mkdir -p "$(dirname "$dir")"
        git clone "$url" "$dir"
    fi

    origin="$(git -C "$dir" config --get remote.origin.url || true)"
    case "$origin" in
      "$url"|"${url%.git}") ;;
      *) die "unexpected git origin in $dir: $origin" ;;
    esac

    git -C "$dir" fetch --depth=1 origin "$commit"
    git -C "$dir" reset --hard "$commit"
    git -C "$dir" clean -fdx
}

echo "[1/4] Preparing pinned Ingenic U-Boot source..."
clone_or_pin "$UBOOT_REPO" "$UBOOT_COMMIT" "$UBOOT_SRC"

echo "[2/4] Preparing pinned MIPS GCC 4.7.2 toolchain..."
clone_or_pin "$TOOLCHAIN_REPO" "$TOOLCHAIN_COMMIT" "$TOOLCHAIN_DIR"
CROSS_COMPILE="$TOOLCHAIN_DIR/bin/mips-linux-gnu-"
[ -x "${CROSS_COMPILE}gcc" ] || die "cross compiler missing: ${CROSS_COMPILE}gcc"

echo "[3/4] Applying T23N SD/MMC boot patch..."
if git -C "$UBOOT_SRC" apply --check "$PATCH" >/dev/null 2>&1; then
    git -C "$UBOOT_SRC" apply "$PATCH"
else
    grep -q '^isvp_t23_msc0 ' "$UBOOT_SRC/boards.cfg" || die "cannot apply T23N SD U-Boot patch"
    grep -q 'root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait init=/init'         "$UBOOT_SRC/include/configs/isvp_t23.h" || die "T23N SD bootargs patch missing"
fi

echo "[4/4] Building T23N U-Boot for direct SD BootROM boot..."
make -C "$UBOOT_SRC" distclean
make -C "$UBOOT_SRC" CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS" isvp_t23_msc0

IMAGE="$UBOOT_SRC/u-boot-with-spl.bin"
[ -f "$IMAGE" ] || die "u-boot-with-spl.bin was not produced"

# T23 SD BootROM path expects the SPL magic at SD sector 34 (17 KiB).
magic="$(od -An -tx4 -N4 "$IMAGE" | tr -d ' \n')"
[ "$magic" = "4d53504c" ] || die "unexpected SPL magic: $magic (expected 4d53504c)"

# U-Boot proper begins at sector 86; its environment begins at sector 514.
# The combined SPL+U-Boot payload written from sector 34 must not overlap env.
size="$(wc -c < "$IMAGE" | tr -d ' ')"
max=$(((514 - 34) * 512))
[ "$size" -le "$max" ] || die "SD bootloader too large: $size > $max bytes"

mkdir -p "$(dirname "$OUT")"
cp "$IMAGE" "$OUT"

echo
echo "T23N SD bootloader built:"
ls -lh "$OUT"
sha256sum "$OUT"
echo
echo "Raw placement on SD: sector 34 (17 KiB)"
echo "U-Boot raw start expected by SPL: sector 86"
echo "Kernel raw slot expected by U-Boot: sector 0x1800 (3 MiB)"
echo "Rootfs expected by U-Boot: /dev/mmcblk0p2 (ext4)"
