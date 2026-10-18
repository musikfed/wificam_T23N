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

die() { echo "ERROR: $*" >&2; exit 1; }

for cmd in git make gcc python3 od sha256sum strings lzop; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd not installed"
done

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

echo "[3/4] Creating T23N SD/MMC U-Boot target..."
python3 - "$UBOOT_SRC" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
boards = root / "boards.cfg"
header = root / "include/configs/isvp_t23.h"

board_text = boards.read_text()
sf_line = (
    "isvp_t23_sfcnor              mips        xburst      isvp_t23"
    "            ingenic        t23         "
    "isvp_t23:SPL_SFC_SUPPORT,ENV_IS_IN_SPI_FLASH,SPL_SFC_NOR,JZ_MMC_MSC0,T23N"
)
mmc_line = (
    "isvp_t23_msc0                mips        xburst      isvp_t23"
    "            ingenic        t23         "
    "isvp_t23:SPL_MMC_SUPPORT,ENV_IS_IN_MMC,GPT_CREATOR,JZ_MMC_MSC0,SFC_COMMAND,T23N"
)
if mmc_line not in board_text:
    if sf_line not in board_text:
        raise SystemExit("cannot find pinned isvp_t23_sfcnor line")
    board_text = board_text.replace(sf_line, sf_line + "\n" + mmc_line, 1)
    boards.write_text(board_text)

header_text = header.read_text()
old = '#define CONFIG_BOOTARGS BOOTARGS_COMMON " init=/linuxrc root=/dev/mmcblk0p2 rw rootdelay=1"'
new = '#define CONFIG_BOOTARGS BOOTARGS_COMMON " root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait init=/init"'
if new not in header_text:
    if old not in header_text:
        raise SystemExit("cannot find pinned T23 MMC bootargs line")
    header_text = header_text.replace(old, new, 1)

old_cmd = '#define CONFIG_BOOTCOMMAND "mmc read 0x80600000 0x1800 0x3000; bootm 0x80600000"'
new_cmd = '#define CONFIG_BOOTCOMMAND "if test \\"$sd_env_initialized\\" != \\"1\\"; then setenv sd_env_initialized 1; saveenv; fi; mmc read 0x80600000 0x1800 0x3000; bootm 0x80600000"'
if new_cmd not in header_text:
    if old_cmd not in header_text:
        raise SystemExit("cannot find pinned T23 MMC boot command")
    header_text = header_text.replace(old_cmd, new_cmd, 1)

header.write_text(header_text)

PY

# OpenIPC's isvp_t23.h includes isvp_common.h last.  That common header
# undefines/redefines bootargs, bootcmd and env for the normal SPI/NOR layout.
# Re-assert the SD-only settings at the END of isvp_common.h, otherwise a
# nominal SPL_MMC_SUPPORT build silently boots with the SPI defaults.
python3 - "$UBOOT_SRC" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
common = root / "include/configs/isvp_common.h"
s = common.read_text()
marker = "/* WIFICAM_T23N_SD_ONLY_EFFECTIVE_CONFIG */"
if marker not in s:
    s = s.rstrip() + r"""

/* WIFICAM_T23N_SD_ONLY_EFFECTIVE_CONFIG */
#ifdef CONFIG_SPL_MMC_SUPPORT
#undef CONFIG_BOOTARGS
#undef CONFIG_BOOTCOMMAND
#undef CONFIG_ENV_OFFSET
#undef CONFIG_ENV_SIZE
#undef CONFIG_ENV_SECT_SIZE
#undef CONFIG_SYS_MONITOR_LEN

#define CONFIG_BOOTARGS BOOTARGS_COMMON " root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait init=/init"
#define CONFIG_BOOTCOMMAND "if test \"$sd_env_initialized\" != \"1\"; then setenv sd_env_initialized 1; saveenv; fi; mmc read 0x80600000 0x1800 0x3000; bootm 0x80600000"

/* T23N autonomous SD raw layout:
 *   SPL             sector 34
 *   U-Boot proper   sector 86
 *   env             0x40400 bytes = sector 514
 *   env size        32 KiB
 */
#define CONFIG_SYS_MONITOR_LEN (214 * 1024)
#define CONFIG_ENV_OFFSET      0x40400
#define CONFIG_ENV_SIZE        (32 << 10)
#define CONFIG_ENV_SECT_SIZE   (32 << 10)
#endif
"""
    common.write_text(s)
PY

grep -q '^isvp_t23_msc0 .*SPL_MMC_SUPPORT.*ENV_IS_IN_MMC.*JZ_MMC_MSC0.*T23N'     "$UBOOT_SRC/boards.cfg" || die "T23N MMC target verification failed"
grep -q 'root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait init=/init'     "$UBOOT_SRC/include/configs/isvp_t23.h" || die "T23N SD bootargs verification failed"
grep -q 'sd_env_initialized.*saveenv.*mmc read 0x80600000 0x1800 0x3000'     "$UBOOT_SRC/include/configs/isvp_t23.h" || die "T23N SD first-boot env initialization missing"
grep -q 'WIFICAM_T23N_SD_ONLY_EFFECTIVE_CONFIG' "$UBOOT_SRC/include/configs/isvp_common.h" || die "effective MMC override missing"
grep -q 'root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait init=/init' "$UBOOT_SRC/include/configs/isvp_common.h" || die "effective SD root bootargs missing"
grep -Eq 'CONFIG_ENV_OFFSET[[:space:]]+0x40400' "$UBOOT_SRC/include/configs/isvp_common.h" || die "effective SD env offset missing"
grep -q 'sd_env_initialized.*saveenv.*mmc read 0x80600000 0x1800 0x3000' "$UBOOT_SRC/include/configs/isvp_common.h" || die "effective SD bootcmd missing"

echo "[4/4] Building T23N U-Boot for direct SD BootROM boot..."
make -C "$UBOOT_SRC" distclean
make -C "$UBOOT_SRC" CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS" isvp_t23_msc0

IMAGE="$UBOOT_SRC/u-boot-with-spl.bin"
[ -f "$IMAGE" ] || die "u-boot-with-spl.bin was not produced"

VERIFY_BIN="$UBOOT_SRC/u-boot"
[ -f "$VERIFY_BIN" ] || VERIFY_BIN="$UBOOT_SRC/u-boot.bin"
[ -f "$VERIFY_BIN" ] || die "compiled U-Boot verification binary missing"
strings "$VERIFY_BIN" | grep -F 'root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait init=/init' >/dev/null || die "compiled U-Boot lacks SD root bootargs"
strings "$VERIFY_BIN" | grep -F 'mmc read 0x80600000 0x1800 0x3000' >/dev/null || die "compiled U-Boot lacks SD kernel bootcmd"

# T23 MMC SPL starts with the MSPL word. The complete image is written to
# SD sector 34, exactly as the Ingenic/OpenIPC raw MMC boot path expects.
magic="$(od -An -tx4 -N4 "$IMAGE" | tr -d ' \n')"
[ "$magic" = "4d53504c" ] || die "unexpected SPL magic: $magic (expected 4d53504c)"

# T23 config: SPL is 26 KiB. With the image placed at sector 34,
# U-Boot proper therefore starts at sector 86. MMC environment begins at
# sector 514, so the combined SPL+U-Boot image must end before it.
size="$(wc -c < "$IMAGE" | tr -d ' ')"
max=$(((514 - 34) * 512))
[ "$size" -le "$max" ] || die "SD bootloader too large: $size > $max bytes"

mkdir -p "$(dirname "$OUT")"
cp "$IMAGE" "$OUT"

echo
echo "T23N AUTONOMOUS SD BOOTLOADER BUILT:"
ls -lh "$OUT"
sha256sum "$OUT"
echo
echo "BootROM raw SPL start : sector 34 (17 KiB)"
echo "U-Boot proper start   : sector 86"
echo "U-Boot env start      : sector 514"
echo "Kernel raw start      : sector 0x1800 (3 MiB)"
echo "Kernel raw read size  : 0x3000 sectors (6 MiB)"
echo "Linux root            : /dev/mmcblk0p2 (ext4)"
echo "First boot             : save full default U-Boot env once to sector 514"
