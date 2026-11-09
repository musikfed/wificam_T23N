#!/bin/sh
set -eu

# Buildroot rejects PATH entries containing spaces/TAB/newlines. Keep the
# build independent from the interactive shell environment.
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CAMERA="${CAMERA:-galayou_g2_t23n_sc2336_atbm6012bx}"
THINGINO_REF="${THINGINO_REF:-9925f46f73b9c39ec8d2a65134b18c94e6fdfb97}"
THINGINO_URL="${THINGINO_URL:-https://github.com/themactep/thingino-firmware.git}"
PUBLISH="${PUBLISH:-0}"
FAST="${THINGINO_FAST:-0}"
# Optional build-time WebRTC for future low-latency camera talkback.
# Off in the smallest profile; never confuse it with the runtime LLM checkbox.
WIFICAM_WEBRTC="${WIFICAM_WEBRTC:-0}"

# A personalized image contains a Wi-Fi network key (WPA2 derived PSK).
# Keep it in gitignored out/private-sd, never overwrite the versioned
# public Thingino/thingino-t23-sd.bin with private LAN credentials.
LOCAL_WIFI="$REPO_DIR/local/wifi.env"
# Never rewrite the hardware-booted 0.1_test baseline in an ordinary factory job.
IMAGE_DIR="$REPO_DIR/out/candidate-sd"
if [ -e "$LOCAL_WIFI" ] || [ -L "$LOCAL_WIFI" ]; then
    [ "$PUBLISH" != 1 ] || { echo "ERROR: refusing PUBLISH=1 with embedded Wi-Fi credentials" >&2; exit 1; }
    IMAGE_DIR="$REPO_DIR/out/private-sd"
elif [ "$PUBLISH" = "1" ]; then
    IMAGE_DIR="$REPO_DIR/Thingino"
fi
IMAGE_PATH="$IMAGE_DIR/thingino-t23-sd.bin"

die() { echo "ERROR: $*" >&2; exit 1; }
case "$WIFICAM_WEBRTC" in 0|1) ;; *) die "WIFICAM_WEBRTC must be 0 or 1" ;; esac
WEBRTC_FRAGMENT='# BR2_PACKAGE_THINGINO_RAPTOR_WEBRTC is not set'
if [ "$WIFICAM_WEBRTC" = 1 ]; then
    WEBRTC_FRAGMENT='BR2_PACKAGE_THINGINO_RAPTOR_WEBRTC=y
BR2_PACKAGE_THINGINO_RAPTOR_TLS=y'
fi

for cmd in git make sha256sum stat find grep debugfs; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd not installed"
done

resolve_thingino_dir() {
    if [ -n "${THINGINO_DIR:-}" ]; then
        printf '%s\n' "$THINGINO_DIR"
        return 0
    fi

    for d in \
        "$HOME/myipcam/thingino-firmware" \
        "$HOME/thingino-firmware" \
        "$HOME/myipcam/Thingino/thingino-firmware"
    do
        if [ -d "$d/.git" ]; then
            printf '%s\n' "$d"
            return 0
        fi
    done

    printf '%s\n' "$HOME/myipcam/thingino-firmware"
}

THINGINO_DIR="$(resolve_thingino_dir)"

prepare_thingino_checkout() {
    if [ ! -d "$THINGINO_DIR/.git" ]; then
        echo "Thingino checkout not found; cloning pinned upstream source..."
        mkdir -p "$(dirname "$THINGINO_DIR")"
        git clone --recurse-submodules "$THINGINO_URL" "$THINGINO_DIR"
    fi

    [ -d "$THINGINO_DIR/.git" ] || die "Thingino checkout unavailable: $THINGINO_DIR"

    if [ -n "$(git -C "$THINGINO_DIR" status --porcelain)" ]; then
        die "Thingino checkout has local changes: $THINGINO_DIR"
    fi

    if ! git -C "$THINGINO_DIR" cat-file -e "$THINGINO_REF^{commit}" 2>/dev/null; then
        echo "Fetching pinned Thingino commit $THINGINO_REF ..."
        git -C "$THINGINO_DIR" fetch origin "$THINGINO_REF"
    fi

    git -C "$THINGINO_DIR" checkout --detach "$THINGINO_REF"
    git -C "$THINGINO_DIR" submodule sync --recursive
    git -C "$THINGINO_DIR" submodule update --init --recursive

    ACTUAL="$(git -C "$THINGINO_DIR" rev-parse HEAD)"
    [ "$ACTUAL" = "$THINGINO_REF" ] || die "Thingino HEAD mismatch: $ACTUAL"

    [ -f "$THINGINO_DIR/configs/cameras/$CAMERA/${CAMERA}_defconfig" ] || \
        die "Thingino camera profile not found: $CAMERA"
}

echo "============================================================"
echo " PegineLab WIFICAM + Thingino MMC image"
echo "============================================================"
echo "Project checkout  : $REPO_DIR"
echo "Thingino checkout : $THINGINO_DIR"
echo "Pinned Thingino   : $THINGINO_REF"
echo "Camera profile    : $CAMERA"
echo "Optional WebRTC   : $WIFICAM_WEBRTC (build-time only)"
echo "Target artifact   : $IMAGE_PATH"
if [ "$IMAGE_DIR" = "$REPO_DIR/out/private-sd" ]; then
    echo "SECURITY: private Wi-Fi PSK image under gitignored out/; PUBLISH=1 blocked."
fi
echo
echo "RU: Web UI является обязательной частью этого образа."
echo "EN: The PegineLab WIFICAM Web UI is a mandatory part of this image."
echo

if [ "$PUBLISH" = "1" ] && ! git -C "$REPO_DIR" diff --cached --quiet; then
    die "refusing PUBLISH=1 because unrelated files are already staged in the project repo"
fi

prepare_thingino_checkout

# MMC mode boots p2/rootfs.ext2 directly. Thingino user/overlay normally feeds
# data.jffs2, which is not mounted as the root device in this SD-root mode.
# Build a dedicated Buildroot rootfs overlay and inject WIFICAM into rootfs.ext2.
ROOTFS_OVERLAY="$REPO_DIR/out/thingino-wificam-rootfs-overlay"
sh "$REPO_DIR/scripts/package_rootfs_overlay.sh" "$ROOTFS_OVERLAY"

USER_ROOT="$REPO_DIR/out/thingino-user"
USER_CAM="$USER_ROOT/$CAMERA"
rm -rf "$USER_CAM"
mkdir -p "$USER_CAM"

# Buildroot's BusyBox package reads fragments only from the Kconfig string
# BR2_PACKAGE_BUSYBOX_CONFIG_FRAGMENT_FILES.  Pinned Thingino also tries to
# append BUSYBOX_KCONFIG_FRAGMENT_FILES from an override .mk, but Buildroot's
# package/busybox/busybox.mk assigns that make variable afterwards and loses
# the append.  Keep our minimal WIFICAM requirements on the supported path.
BUSYBOX_WIFICAM_FRAGMENT="$USER_CAM/busybox-wificam.fragment"
cat > "$BUSYBOX_WIFICAM_FRAGMENT" <<'EOF'
CONFIG_HTTPD=y
CONFIG_FEATURE_HTTPD_CGI=y
CONFIG_FEATURE_HTTPD_BASIC_AUTH=y
# A CGI preflight must be able to fetch loopback HTTP even if curl is absent.
CONFIG_WGET=y
# CGI requires fork+exec: FEATURE_FORCE_APPLETS and CGI are incompatible.
# CONFIG_FEATURE_FORCE_APPLETS is not set
EOF

cat > "$USER_CAM/local.fragment" <<EOF
# PegineLab WIFICAM T23N SD-root build
BR2_PACKAGE_THINGINO_KOPT_MMC0=y
BR2_PACKAGE_THINGINO_KOPT_MMC0_1BIT=y
BR2_PACKAGE_THINGINO_KOPT_MMC0_BOOT=y
BR2_PACKAGE_THINGINO_UBOOT_ROOT="/dev/mmcblk0p2"
BR2_PACKAGE_THINGINO_UBOOT_ROOTFSTYPE="ext4"
BR2_TARGET_ROOTFS_EXT2=y
BR2_TARGET_ROOTFS_EXT2_4=y
BR2_TARGET_ROOTFS_EXT2_MKFS_OPTIONS="-O ^metadata_csum,^64bit,^orphan_file"
BR2_TARGET_ROOTFS_EXT2_SIZE="64M"

# PegineLab WIFICAM deliberately uses BusyBox httpd as the smallest CGI server.
# Required by our current admin: httpd + CGI + Basic Auth.
# 0.1_test uses the hardware-verified plaintext BusyBox auth format.
BR2_PACKAGE_THINGINO_WEBSERVER_BUSYBOX=y
BR2_PACKAGE_BUSYBOX_CONFIG_FRAGMENT_FILES="$BUSYBOX_WIFICAM_FRAGMENT"

# Lean T23N Raptor: keep sensor/RTSP/snapshots/audio/OSD/night/recording/motion.
# Exclude transport daemons unnecessary for local Wi-Fi WIFICAM and RTSP.
# This does NOT disable the Ingenic ISP, USB DWC2 Wi-Fi, PTZ or SD/MMC.
BR2_PACKAGE_THINGINO_STREAMER_RAPTOR=y
# BR2_PACKAGE_THINGINO_RAPTOR_FULL is not set
BR2_PACKAGE_THINGINO_RAPTOR_RVD=y
BR2_PACKAGE_THINGINO_RAPTOR_RSD=y
BR2_PACKAGE_THINGINO_RAPTOR_RAD=y
# Required for actual built-in speaker playback: provides rac + play wrapper.
BR2_PACKAGE_THINGINO_RAPTOR_RAC=y
BR2_PACKAGE_THINGINO_RAPTOR_RHD=y
BR2_PACKAGE_THINGINO_RAPTOR_ROD=y
BR2_PACKAGE_THINGINO_RAPTOR_RIC=y
BR2_PACKAGE_THINGINO_RAPTOR_RMR=y
BR2_PACKAGE_THINGINO_RAPTOR_RMD=y
$WEBRTC_FRAGMENT
# BR2_PACKAGE_THINGINO_RAPTOR_WEBTORRENT is not set
# BR2_PACKAGE_THINGINO_RAPTOR_RSP is not set
# BR2_PACKAGE_THINGINO_RAPTOR_RSR is not set
# BR2_PACKAGE_THINGINO_RAPTOR_RWC is not set
# BR2_PACKAGE_THINGINO_RAPTOR_RFS is not set
# BR2_PACKAGE_THINGINO_RAPTOR_RSD555 is not set
# BR2_PACKAGE_THINGINO_RAPTOR_DEBUG is not set

# Mandatory PegineLab/WIFICAM files are embedded directly into p2/rootfs.ext2.
BR2_ROOTFS_OVERLAY="\$(BR2_EXTERNAL_THINGINO_PATH)/overlay $ROOTFS_OVERLAY"
EOF

THINGINO_COMMIT="$(git -C "$THINGINO_DIR" rev-parse HEAD)"
echo "Thingino commit   : $THINGINO_COMMIT"

if [ "$FAST" = "1" ]; then
    BUILD_TARGET=fast
else
    BUILD_TARGET=cleanbuild
fi

echo "Build target      : $BUILD_TARGET"
echo

(
    cd "$THINGINO_DIR"
    env IP= THINGINO_USER_DIR="$USER_ROOT" \
        make CAMERA="$CAMERA" "$BUILD_TARGET"
)

SPI_IMAGE="$(find "$THINGINO_DIR/output" -type f -path "*/images/thingino-$CAMERA.bin" -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n1 | cut -d' ' -f2-)"
[ -n "$SPI_IMAGE" ] && [ -f "$SPI_IMAGE" ] || die "built Thingino SPI image not found"

# The normal thingino-$CAMERA.bin is the 8 MiB SFC/SPI flash image.
# It is NOT a direct SD disk image and must never be published as one.
OUTDIR="$(dirname "$(dirname "$SPI_IMAGE")")"
ROOTFS_EXT="$OUTDIR/images/rootfs.ext2"
TARGET="$OUTDIR/target"
KERNEL_IMAGE="$OUTDIR/images/uImage"
FINAL_CONFIG="$OUTDIR/.config"

[ -f "$FINAL_CONFIG" ] || die "final Thingino .config missing: $FINAL_CONFIG"

# Hardware-specific, pinned upstream Galayou G2: T23N + SC2336 + USB
# ATBM6012BX (requires DWC2) + MMC0 SD-root + GPIO motors + audio.
# Fail rather than silently ship a fast but unusable image.
[ "$CAMERA" = "galayou_g2_t23n_sc2336_atbm6012bx" ] || die "wrong camera: $CAMERA"
for required in \
    'BR2_INGENIC_SOC_MODEL="t23n"' \
    'BR2_SENSOR_1_NAME="sc2336"' \
    'BR2_PACKAGE_WIFI=y' \
    'BR2_PACKAGE_WIFI_ATBM6012BX=y' \
    'BR2_PACKAGE_THINGINO_KOPT_DWC2=y' \
    'BR2_PACKAGE_THINGINO_KOPT_DWC2_WIFI_ONLY=y' \
    'BR2_PACKAGE_THINGINO_KOPT_MMC0=y' \
    'BR2_PACKAGE_THINGINO_KOPT_MMC0_1BIT=y' \
    'BR2_THINGINO_SDCARD=y' \
    'BR2_THINGINO_MOTORS=y' \
    'BR2_THINGINO_AUDIO=y' \
    'BR2_PACKAGE_THINGINO_RAPTOR_RAC=y' \
    'BR2_PACKAGE_THINGINO_STREAMER_RAPTOR=y'
do
    grep -Fqx "$required" "$FINAL_CONFIG" || die "T23N hardware feature missing: $required"
done
for component in RVD RSD RAD RHD ROD RIC RMR RMD; do
    grep -Fqx "BR2_PACKAGE_THINGINO_RAPTOR_$component=y" "$FINAL_CONFIG" ||
        die "required lightweight Raptor daemon missing: $component"
done
if [ "$WIFICAM_WEBRTC" = 1 ]; then
    grep -Fqx 'BR2_PACKAGE_THINGINO_RAPTOR_WEBRTC=y' "$FINAL_CONFIG" ||
        die "WIFICAM_WEBRTC=1 requested but final WebRTC is disabled"
else
    if grep -Fqx 'BR2_PACKAGE_THINGINO_RAPTOR_WEBRTC=y' "$FINAL_CONFIG"; then
        die "WebRTC enabled unexpectedly in minimal T23N profile"
    fi
fi
for component in FULL WEBTORRENT RSP RSR RWC RFS RSD555 DEBUG; do
    if grep -Fqx "BR2_PACKAGE_THINGINO_RAPTOR_$component=y" "$FINAL_CONFIG"; then
        die "unneeded Raptor feature enabled in T23N lean profile: $component"
    fi
done
grep -q '^BR2_TARGET_ROOTFS_EXT2=y$' "$FINAL_CONFIG" || \
    die "BR2_TARGET_ROOTFS_EXT2 is not enabled in final Thingino config"
grep -q '^BR2_TARGET_ROOTFS_EXT2_4=y$' "$FINAL_CONFIG" || \
    die "BR2_TARGET_ROOTFS_EXT2_4 is not enabled in final Thingino config"
grep -q '^BR2_PACKAGE_DROPBEAR=ygrep -Fq "BR2_PACKAGE_BUSYBOX_CONFIG_FRAGMENT_FILES=\"$BUSYBOX_WIFICAM_FRAGMENT\"" "$FINAL_CONFIG" || \
    die "WIFICAM BusyBox fragment path did not reach final Buildroot config"

# FAST builds can reuse an older BusyBox .config from before local.fragment
# selected BusyBox httpd. The config is not "missing" in that case; it is
# stale. Reconfigure BusyBox only when one of the four features actually used
# by PegineLab WIFICAM is absent.
BUSYBOX_REQUIRED_OPTS="
CONFIG_HTTPD
CONFIG_FEATURE_HTTPD_BASIC_AUTH
CONFIG_FEATURE_HTTPD_CGI
CONFIG_WGET
"

busybox_config_path() {
    find "$OUTDIR/build" -path '*/busybox-*/.config' -type f | head -n1
}

BUSYBOX_CONFIG="$(busybox_config_path)"
BUSYBOX_NEEDS_RECONFIGURE=0
if [ -z "$BUSYBOX_CONFIG" ] || [ ! -f "$BUSYBOX_CONFIG" ]; then
    BUSYBOX_NEEDS_RECONFIGURE=1
else
    for opt in $BUSYBOX_REQUIRED_OPTS; do
        grep -q "^$opt=y$" "$BUSYBOX_CONFIG" || BUSYBOX_NEEDS_RECONFIGURE=1
    done
fi

if [ "$BUSYBOX_NEEDS_RECONFIGURE" = "1" ]; then
    echo
    echo "BusyBox HTTP config is stale/incomplete; reconfiguring BusyBox..."
    (
        cd "$THINGINO_DIR"
        env IP= THINGINO_USER_DIR="$USER_ROOT" \
            make CAMERA="$CAMERA" br-busybox-reconfigure
    )
    BUSYBOX_CONFIG="$(busybox_config_path)"
fi

[ -n "$BUSYBOX_CONFIG" ] && [ -f "$BUSYBOX_CONFIG" ] || die "BusyBox .config not found after reconfigure"
for opt in $BUSYBOX_REQUIRED_OPTS; do
    if ! grep -q "^$opt=y$" "$BUSYBOX_CONFIG"; then
        echo "BusyBox HTTP config after reconfigure:" >&2
        grep -E '^(# )?CONFIG_(HTTPD|FEATURE_HTTPD_(CGI|BASIC_AUTH))' "$BUSYBOX_CONFIG" >&2 || true
        die "BusyBox HTTP feature missing after reconfigure: $opt"
    fi
done
if grep -q '^CONFIG_FEATURE_FORCE_APPLETS=y$' "$BUSYBOX_CONFIG"; then
    die "BusyBox FEATURE_FORCE_APPLETS prevents CGI exec; disable it in the fragment"
fi

# A valid BusyBox .config is NOT proof that the cached MIPS binary includes
# CGI. We saw this on the hardware-booted 0.1_test: /cgi-bin/api was served
# literally as "#!/bin/sh", despite the .config checks passing. Force an
# incremental BusyBox rebuild before packaging p2; no kernel rebuild needed.
echo
echo "Rebuilding target BusyBox with CGI options; real execution still requires camera smoke testing..."
(
    cd "$THINGINO_DIR"
    env IP= THINGINO_USER_DIR="$USER_ROOT" \
        make CAMERA="$CAMERA" br-busybox-rebuild
)

# Always regenerate rootfs.ext2 after the BusyBox check.  This guarantees that
# a repaired BusyBox binary and the current WIFICAM overlay are both inside p2.
echo
echo "Generating configured ext4 SD rootfs via Buildroot rootfs-ext2..."
rm -f "$ROOTFS_EXT"
(
    cd "$THINGINO_DIR"
    env IP= THINGINO_USER_DIR="$USER_ROOT" \
        make CAMERA="$CAMERA" rootfs-ext2
)

[ -f "$ROOTFS_EXT" ] || die "rootfs.ext2 missing after rootfs-ext2: $ROOTFS_EXT"
[ -f "$KERNEL_IMAGE" ] || die "uImage missing: $KERNEL_IMAGE"
[ -f "$TARGET/usr/share/wificam-web/index.html" ] || die "WIFICAM index missing from Thingino target rootfs"
[ -x "$TARGET/etc/init.d/S90wificam" ] || die "S90wificam missing/not executable in target rootfs"
[ -x "$TARGET/etc/init.d/S94peginelab-audio" ] ||
    die "PegineLab Raptor boot audio init absent/not executable"
[ -s "$TARGET/usr/share/wificam-web/assets/boot-jingle.s16le" ] ||
    die "PegineLab camera native PCM jingle absent from final rootfs"
[ "$(stat -c '%s' "$TARGET/usr/share/wificam-web/assets/boot-jingle.s16le")" -eq 224000 ] ||
    die "PegineLab camera native PCM jingle has unexpected size"
[ -s "$TARGET/usr/share/wificam-web/assets/boot-jingle.wav" ] ||
    die "PegineLab original WAV jingle absent from final rootfs"

[ -x "$TARGET/usr/share/wificam-web/cgi-bin/api" ] || die "WIFICAM API missing/not executable"
[ -x "$TARGET/usr/share/wificam-web/cgi-bin/snapshot.jpg" ] || die "snapshot CGI missing/not executable"
[ -x "$TARGET/usr/share/wificam-web/cgi-bin/live.mjpg" ] || die "native MJPEG CGI missing/not executable"
[ -x "$TARGET/usr/bin/wificam-ptz-ctl" ] || die "Thingino PTZ controller missing/not executable"
[ -f "$TARGET/usr/share/wificam-web/setup/index.html" ] || die "WIFICAM first-boot setup page missing"
[ -x "$TARGET/usr/share/wificam-web/setup/cgi-bin/claim" ] || die "WIFICAM first-boot claim CGI missing/not executable"
# A voice companion must use this camera's OWN microphone and speaker.
# Shipping RAD without rac/play made the checkbox look functional but the
# speaker cannot output Hombo3 TTS. Ensure each tool reaches final rootfs.
for audio_tool in \
    /usr/bin/rac \
    /usr/sbin/play \
    /usr/sbin/microphone \
    /usr/sbin/speaker
do
    [ -x "$TARGET$audio_tool" ] || die "T23N camera audio tool missing: $audio_tool"
done
[ -x "$TARGET/usr/sbin/dropbear" ] || die "Dropbear binary missing from target rootfs"
if [ ! -x "$TARGET/etc/init.d/S30dropbear" ] && [ ! -x "$TARGET/etc/init.d/S50dropbear" ]; then
    die "Dropbear init script missing from target rootfs"
fi

# If private Wi-Fi provisioning was requested, verify that both the
# Buildroot target and the ACTUAL ext4 image contain the generated config.
# Never print it: the derived WPA2 PSK is password-equivalent.
# Only an explicitly provisioned private build contains a generated WPA2 PSK.
# Ordinary PUBLISH=0 builds under out/candidate-sd have NO local/wifi.env;
# requiring that private file here would make the factory job fail after the
# expensive cross-compilation despite a valid generic SD image.
if [ "$IMAGE_DIR" = "$REPO_DIR/out/private-sd" ]; then
    [ -f "$TARGET/etc/wpa_supplicant.conf" ] || die "private Wi-Fi missing from target"
    grep -q '^# PegineLab: generated locally' "$TARGET/etc/wpa_supplicant.conf" || \
        die "Buildroot overwrote private Wi-Fi target configuration"
    debugfs -R 'cat /etc/wpa_supplicant.conf' "$ROOTFS_EXT" 2>/dev/null | \
        grep -q '^# PegineLab: generated locally' || \
        die "private Wi-Fi config did not reach rootfs.ext2"
    echo "Wi-Fi private config: verified INSIDE rootfs.ext2 (contents hidden)"
fi

grep -q '^WEB_PORT=8090$' "$TARGET/etc/wificam/wificam.conf" || \
    die "WIFICAM WEB_PORT is not 8090"
grep -q '^AUTO_PROVISION_TEST_WEB_AUTH=1$' "$TARGET/etc/wificam/wificam.conf" || \
    die "0.1_test web auth auto-provision is not enabled"
grep -q '^DEFAULT_WEB_USER=admin$' "$TARGET/etc/wificam/wificam.conf" || \
    die "0.1_test default web user mismatch"
grep -q '^DEFAULT_WEB_PASSWORD=Wificam12345$' "$TARGET/etc/wificam/wificam.conf" || \
    die "0.1_test default web password mismatch"
grep -q '^AUTH_PASSWORD_MODE=plain$' "$TARGET/etc/wificam/wificam.conf" || \
    die "0.1_test BusyBox auth compatibility mode is not plain"
grep -q '^SSH_PROTECT=1$' "$TARGET/etc/wificam/wificam.conf" || \
    die "SSH_PROTECT=1 missing from WIFICAM config"
grep -q 'BOOTSTRAP_CONF=' "$TARGET/etc/init.d/S90wificam" || \
    die "S90wificam does not isolate bootstrap httpd config from Thingino"
grep -q 'start_httpd .*BOOTSTRAP_CONF' "$TARGET/etc/init.d/S90wificam" || \
    die "S90wificam bootstrap does not pass a private -c config"
if grep -q 'od -A' "$TARGET/etc/init.d/S90wificam"; then
    die "S90wificam uses BusyBox-incompatible od -A option"
fi
grep -q "printf 'H:%s" "$TARGET/usr/bin/wificam-set-web-password" || \
    die "WIFICAM password helper does not write canonical BusyBox H: webroot"

grep -q 'PegineLab WIFICAM T23N' "$TARGET/usr/share/wificam-web/index.html" || \
    die "wrong Web UI staged in target"
grep -q '^BR2_PACKAGE_THINGINO_KOPT_MMC0_BOOT=y$' "$FINAL_CONFIG" || \
    die "MMC0_BOOT is not enabled in final Thingino config"
grep -q '^BR2_PACKAGE_THINGINO_UBOOT_ROOT="/dev/mmcblk0p2"$' "$FINAL_CONFIG" || \
    die "U-Boot root is not /dev/mmcblk0p2"
grep -q '^BR2_PACKAGE_THINGINO_WEBSERVER_BUSYBOX=y$' "$FINAL_CONFIG" || \
    die "Thingino BusyBox webserver choice is not enabled"

debugfs -R 'stat /usr/share/wificam-web/index.html' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM index is absent from rootfs.ext2"
debugfs -R 'stat /etc/init.d/S90wificam' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "S90wificam is absent from rootfs.ext2"
for boot_asset in \
    /etc/init.d/S94peginelab-audio \
    /usr/share/wificam-web/assets/boot-jingle.s16le \
    /usr/share/wificam-web/assets/boot-jingle.wav
do
    debugfs -R "stat $boot_asset" "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' ||
        die "PegineLab boot melody missing inside ext4: $boot_asset"
done
debugfs -R 'stat /usr/share/wificam-web/cgi-bin/api' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM API is absent from rootfs.ext2"
debugfs -R 'stat /usr/share/wificam-web/cgi-bin/snapshot.jpg' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM snapshot CGI is absent from rootfs.ext2"
debugfs -R 'stat /usr/share/wificam-web/setup/index.html' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM first-boot setup page is absent from rootfs.ext2"
debugfs -R 'stat /usr/share/wificam-web/setup/cgi-bin/claim' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM first-boot claim CGI is absent from rootfs.ext2"
for audio_tool in /usr/bin/rac /usr/sbin/play /usr/sbin/microphone /usr/sbin/speaker; do
    debugfs -R "stat $audio_tool" "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
        die "T23N microphone/speaker tool missing from SD rootfs: $audio_tool"
done
debugfs -R 'stat /usr/sbin/dropbear' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "Dropbear SSH binary is absent from rootfs.ext2"
if ! debugfs -R 'stat /etc/init.d/S30dropbear' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:'; then
    debugfs -R 'stat /etc/init.d/S50dropbear' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
        die "Dropbear init script is absent from rootfs.ext2"
fi

if command -v dumpe2fs >/dev/null 2>&1; then
    ROOTFS_FEATURES="$(dumpe2fs -h "$ROOTFS_EXT" 2>/dev/null | sed -n 's/^Filesystem features:[[:space:]]*//p')"
    case " $ROOTFS_FEATURES " in
      *" 64bit "*|*" metadata_csum "*|*" orphan_file "*)
        die "rootfs.ext2 contains ext4 features unsupported by Linux 3.10: $ROOTFS_FEATURES"
        ;;
    esac
fi

# Use the separately pinned T23N MMC SPL/U-Boot, not the sfcnor U-Boot from
# the 8 MiB SPI image, then assemble a real partitioned SD disk image.
sh "$REPO_DIR/scripts/build_sd_bootloader.sh"

mkdir -p "$IMAGE_DIR"
sh "$REPO_DIR/scripts/assemble_thingino_wificam_sd_image.sh" \
    "$REPO_DIR/out/u-boot-t23n-sd.bin" \
    "$KERNEL_IMAGE" \
    "$ROOTFS_EXT" \
    "$IMAGE_PATH"

IMAGE_SIZE="$(stat -c '%s' "$IMAGE_PATH")"
IMAGE_SHA="$(sha256sum "$IMAGE_PATH" | awk '{print $1}')"

HISTORICAL_REFERENCE="/mnt/d/Thingino/thingino-t23-sd.bin"
HISTORICAL_SHA="not-present"
HISTORICAL_SIZE="not-present"
if [ -f "$HISTORICAL_REFERENCE" ]; then
    HISTORICAL_SHA="$(sha256sum "$HISTORICAL_REFERENCE" | awk '{print $1}')"
    HISTORICAL_SIZE="$(stat -c '%s' "$HISTORICAL_REFERENCE")"
fi

MAX_GITHUB_SIZE=$((95 * 1024 * 1024))
[ "$IMAGE_SIZE" -le "$MAX_GITHUB_SIZE" ] || \
    die "canonical image is $IMAGE_SIZE bytes; refusing Git publish above 95 MiB"

printf '%s  %s\n' "$IMAGE_SHA" "thingino-t23-sd.bin" > "$IMAGE_PATH.sha256"

cat > "$IMAGE_DIR/IMAGE_INFO.txt" <<EOF
PegineLab WIFICAM T23N — canonical Thingino MMC SD candidate

RU:
Профиль-кандидат: $CAMERA
Источник Thingino: $THINGINO_COMMIT
Файл: $IMAGE_PATH
Размер: $IMAGE_SIZE bytes
SHA256: $IMAGE_SHA
Исторический локальный reference: $HISTORICAL_REFERENCE
Reference size: $HISTORICAL_SIZE
Reference SHA256: $HISTORICAL_SHA
Web UI: ОБЯЗАТЕЛЬНО ПРОВЕРЕНА в rootfs.ext2
Web URL после загрузки: http://CAMERA_IP:8090/
Web login: admin / Wificam12345 (0.1_test LAN-only)
SSH: Dropbear TCP 22, обязательный recovery channel
Root: /dev/mmcblk0p2 ext4
Назначение: прямой MMC/SD boot image, НЕ autoupdate payload во SPI.

EN:
Candidate profile: $CAMERA
Thingino source: $THINGINO_COMMIT
File: $IMAGE_PATH
Size: $IMAGE_SIZE bytes
SHA256: $IMAGE_SHA
Historical local reference: $HISTORICAL_REFERENCE
Reference size: $HISTORICAL_SIZE
Reference SHA256: $HISTORICAL_SHA
Web UI: MANDATORY and VERIFIED inside rootfs.ext2
Web URL after boot: http://CAMERA_IP:8090/
Web login: admin / Wificam12345 (0.1_test LAN-only)
SSH: Dropbear TCP 22, mandatory recovery channel
Root: /dev/mmcblk0p2 ext4
Purpose: direct MMC/SD boot image, NOT an SPI autoupdate payload.
EOF

echo
echo "THINGINO WIFICAM SD IMAGE: VERIFIED"
echo "SPI artifact  : $SPI_IMAGE"
echo "Canonical     : $IMAGE_PATH"
echo "Size          : $IMAGE_SIZE bytes"
echo "SHA256        : $IMAGE_SHA"
echo "Historical    : $HISTORICAL_REFERENCE"
echo "Historical SHA: $HISTORICAL_SHA"
echo "Web UI        : FILES VERIFIED inside p2 rootfs.ext2 (CGI execution NOT YET proven)"
echo "Hardware CGI  : PENDING — run scripts/camera_smoke_httpd_cgi.sh on camera"
echo "Security      : S90wificam must refuse port 8090 if CGI source would be exposed"
echo "Web URL       : http://CAMERA_IP:8090/"
echo

if [ "$PUBLISH" = "1" ]; then
    [ "$IMAGE_DIR" = "$REPO_DIR/Thingino" ] || die "private Wi-Fi image cannot be published"
    BRANCH="$(git -C "$REPO_DIR" branch --show-current)"
    [ "$BRANCH" = "mymarrchWFcam" ] || die "refusing publish from branch: $BRANCH"

    git -C "$REPO_DIR" add -f \
        Thingino/thingino-t23-sd.bin \
        Thingino/thingino-t23-sd.bin.sha256 \
        Thingino/IMAGE_INFO.txt

    if git -C "$REPO_DIR" diff --cached --quiet; then
        echo "Git: canonical image already committed."
    else
        git -C "$REPO_DIR" commit -m "firmware(thingino): verify relevant T23N SD image with WIFICAM / проверка релевантного T23N SD образа с WIFICAM"
    fi

    git -C "$REPO_DIR" push origin "$BRANCH"
    echo "Git publish: OK ($BRANCH)"
else
    echo "Not pushed. To build + commit + push in one run:"
    echo "  PUBLISH=1 sh scripts/build_thingino_wificam_image.sh  # only without local/wifi.env"
fi
 "$FINAL_CONFIG" || \
    die "Dropbear SSH is not enabled; local recovery access is mandatory"
# CGI verification is fail-closed on hardware; do not ship a rootfs without
# an HTTP client to perform the local JSON probe.

grep -Fq "BR2_PACKAGE_BUSYBOX_CONFIG_FRAGMENT_FILES=\"$BUSYBOX_WIFICAM_FRAGMENT\"" "$FINAL_CONFIG" || \
    die "WIFICAM BusyBox fragment path did not reach final Buildroot config"

# FAST builds can reuse an older BusyBox .config from before local.fragment
# selected BusyBox httpd. The config is not "missing" in that case; it is
# stale. Reconfigure BusyBox only when one of the four features actually used
# by PegineLab WIFICAM is absent.
BUSYBOX_REQUIRED_OPTS="
CONFIG_HTTPD
CONFIG_FEATURE_HTTPD_BASIC_AUTH
CONFIG_FEATURE_HTTPD_CGI
CONFIG_WGET
"

busybox_config_path() {
    find "$OUTDIR/build" -path '*/busybox-*/.config' -type f | head -n1
}

BUSYBOX_CONFIG="$(busybox_config_path)"
BUSYBOX_NEEDS_RECONFIGURE=0
if [ -z "$BUSYBOX_CONFIG" ] || [ ! -f "$BUSYBOX_CONFIG" ]; then
    BUSYBOX_NEEDS_RECONFIGURE=1
else
    for opt in $BUSYBOX_REQUIRED_OPTS; do
        grep -q "^$opt=y$" "$BUSYBOX_CONFIG" || BUSYBOX_NEEDS_RECONFIGURE=1
    done
fi

if [ "$BUSYBOX_NEEDS_RECONFIGURE" = "1" ]; then
    echo
    echo "BusyBox HTTP config is stale/incomplete; reconfiguring BusyBox..."
    (
        cd "$THINGINO_DIR"
        env IP= THINGINO_USER_DIR="$USER_ROOT" \
            make CAMERA="$CAMERA" br-busybox-reconfigure
    )
    BUSYBOX_CONFIG="$(busybox_config_path)"
fi

[ -n "$BUSYBOX_CONFIG" ] && [ -f "$BUSYBOX_CONFIG" ] || die "BusyBox .config not found after reconfigure"
for opt in $BUSYBOX_REQUIRED_OPTS; do
    if ! grep -q "^$opt=y$" "$BUSYBOX_CONFIG"; then
        echo "BusyBox HTTP config after reconfigure:" >&2
        grep -E '^(# )?CONFIG_(HTTPD|FEATURE_HTTPD_(CGI|BASIC_AUTH))' "$BUSYBOX_CONFIG" >&2 || true
        die "BusyBox HTTP feature missing after reconfigure: $opt"
    fi
done
if grep -q '^CONFIG_FEATURE_FORCE_APPLETS=y$' "$BUSYBOX_CONFIG"; then
    die "BusyBox FEATURE_FORCE_APPLETS prevents CGI exec; disable it in the fragment"
fi

# A valid BusyBox .config is NOT proof that the cached MIPS binary includes
# CGI. We saw this on the hardware-booted 0.1_test: /cgi-bin/api was served
# literally as "#!/bin/sh", despite the .config checks passing. Force an
# incremental BusyBox rebuild before packaging p2; no kernel rebuild needed.
echo
echo "Rebuilding target BusyBox with CGI options; real execution still requires camera smoke testing..."
(
    cd "$THINGINO_DIR"
    env IP= THINGINO_USER_DIR="$USER_ROOT" \
        make CAMERA="$CAMERA" br-busybox-rebuild
)

# Always regenerate rootfs.ext2 after the BusyBox check.  This guarantees that
# a repaired BusyBox binary and the current WIFICAM overlay are both inside p2.
echo
echo "Generating configured ext4 SD rootfs via Buildroot rootfs-ext2..."
rm -f "$ROOTFS_EXT"
(
    cd "$THINGINO_DIR"
    env IP= THINGINO_USER_DIR="$USER_ROOT" \
        make CAMERA="$CAMERA" rootfs-ext2
)

[ -f "$ROOTFS_EXT" ] || die "rootfs.ext2 missing after rootfs-ext2: $ROOTFS_EXT"
[ -f "$KERNEL_IMAGE" ] || die "uImage missing: $KERNEL_IMAGE"
[ -f "$TARGET/usr/share/wificam-web/index.html" ] || die "WIFICAM index missing from Thingino target rootfs"
[ -x "$TARGET/etc/init.d/S90wificam" ] || die "S90wificam missing/not executable in target rootfs"
[ -x "$TARGET/etc/init.d/S94peginelab-audio" ] ||
    die "PegineLab Raptor boot audio init absent/not executable"
[ -s "$TARGET/usr/share/wificam-web/assets/boot-jingle.s16le" ] ||
    die "PegineLab camera native PCM jingle absent from final rootfs"
[ "$(stat -c '%s' "$TARGET/usr/share/wificam-web/assets/boot-jingle.s16le")" -eq 224000 ] ||
    die "PegineLab camera native PCM jingle has unexpected size"
[ -s "$TARGET/usr/share/wificam-web/assets/boot-jingle.wav" ] ||
    die "PegineLab original WAV jingle absent from final rootfs"

[ -x "$TARGET/usr/share/wificam-web/cgi-bin/api" ] || die "WIFICAM API missing/not executable"
[ -x "$TARGET/usr/share/wificam-web/cgi-bin/snapshot.jpg" ] || die "snapshot CGI missing/not executable"
[ -x "$TARGET/usr/share/wificam-web/cgi-bin/live.mjpg" ] || die "native MJPEG CGI missing/not executable"
[ -x "$TARGET/usr/bin/wificam-ptz-ctl" ] || die "Thingino PTZ controller missing/not executable"
[ -f "$TARGET/usr/share/wificam-web/setup/index.html" ] || die "WIFICAM first-boot setup page missing"
[ -x "$TARGET/usr/share/wificam-web/setup/cgi-bin/claim" ] || die "WIFICAM first-boot claim CGI missing/not executable"
# A voice companion must use this camera's OWN microphone and speaker.
# Shipping RAD without rac/play made the checkbox look functional but the
# speaker cannot output Hombo3 TTS. Ensure each tool reaches final rootfs.
for audio_tool in \
    /usr/bin/rac \
    /usr/sbin/play \
    /usr/sbin/microphone \
    /usr/sbin/speaker
do
    [ -x "$TARGET$audio_tool" ] || die "T23N camera audio tool missing: $audio_tool"
done
[ -x "$TARGET/usr/sbin/dropbear" ] || die "Dropbear binary missing from target rootfs"
if [ ! -x "$TARGET/etc/init.d/S30dropbear" ] && [ ! -x "$TARGET/etc/init.d/S50dropbear" ]; then
    die "Dropbear init script missing from target rootfs"
fi

# If private Wi-Fi provisioning was requested, verify that both the
# Buildroot target and the ACTUAL ext4 image contain the generated config.
# Never print it: the derived WPA2 PSK is password-equivalent.
# Only an explicitly provisioned private build contains a generated WPA2 PSK.
# Ordinary PUBLISH=0 builds under out/candidate-sd have NO local/wifi.env;
# requiring that private file here would make the factory job fail after the
# expensive cross-compilation despite a valid generic SD image.
if [ "$IMAGE_DIR" = "$REPO_DIR/out/private-sd" ]; then
    [ -f "$TARGET/etc/wpa_supplicant.conf" ] || die "private Wi-Fi missing from target"
    grep -q '^# PegineLab: generated locally' "$TARGET/etc/wpa_supplicant.conf" || \
        die "Buildroot overwrote private Wi-Fi target configuration"
    debugfs -R 'cat /etc/wpa_supplicant.conf' "$ROOTFS_EXT" 2>/dev/null | \
        grep -q '^# PegineLab: generated locally' || \
        die "private Wi-Fi config did not reach rootfs.ext2"
    echo "Wi-Fi private config: verified INSIDE rootfs.ext2 (contents hidden)"
fi

grep -q '^WEB_PORT=8090$' "$TARGET/etc/wificam/wificam.conf" || \
    die "WIFICAM WEB_PORT is not 8090"
grep -q '^AUTO_PROVISION_TEST_WEB_AUTH=1$' "$TARGET/etc/wificam/wificam.conf" || \
    die "0.1_test web auth auto-provision is not enabled"
grep -q '^DEFAULT_WEB_USER=admin$' "$TARGET/etc/wificam/wificam.conf" || \
    die "0.1_test default web user mismatch"
grep -q '^DEFAULT_WEB_PASSWORD=Wificam12345$' "$TARGET/etc/wificam/wificam.conf" || \
    die "0.1_test default web password mismatch"
grep -q '^AUTH_PASSWORD_MODE=plain$' "$TARGET/etc/wificam/wificam.conf" || \
    die "0.1_test BusyBox auth compatibility mode is not plain"
grep -q '^SSH_PROTECT=1$' "$TARGET/etc/wificam/wificam.conf" || \
    die "SSH_PROTECT=1 missing from WIFICAM config"
grep -q 'BOOTSTRAP_CONF=' "$TARGET/etc/init.d/S90wificam" || \
    die "S90wificam does not isolate bootstrap httpd config from Thingino"
grep -q 'start_httpd .*BOOTSTRAP_CONF' "$TARGET/etc/init.d/S90wificam" || \
    die "S90wificam bootstrap does not pass a private -c config"
if grep -q 'od -A' "$TARGET/etc/init.d/S90wificam"; then
    die "S90wificam uses BusyBox-incompatible od -A option"
fi
grep -q "printf 'H:%s" "$TARGET/usr/bin/wificam-set-web-password" || \
    die "WIFICAM password helper does not write canonical BusyBox H: webroot"

grep -q 'PegineLab WIFICAM T23N' "$TARGET/usr/share/wificam-web/index.html" || \
    die "wrong Web UI staged in target"
grep -q '^BR2_PACKAGE_THINGINO_KOPT_MMC0_BOOT=y$' "$FINAL_CONFIG" || \
    die "MMC0_BOOT is not enabled in final Thingino config"
grep -q '^BR2_PACKAGE_THINGINO_UBOOT_ROOT="/dev/mmcblk0p2"$' "$FINAL_CONFIG" || \
    die "U-Boot root is not /dev/mmcblk0p2"
grep -q '^BR2_PACKAGE_THINGINO_WEBSERVER_BUSYBOX=y$' "$FINAL_CONFIG" || \
    die "Thingino BusyBox webserver choice is not enabled"

debugfs -R 'stat /usr/share/wificam-web/index.html' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM index is absent from rootfs.ext2"
debugfs -R 'stat /etc/init.d/S90wificam' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "S90wificam is absent from rootfs.ext2"
for boot_asset in \
    /etc/init.d/S94peginelab-audio \
    /usr/share/wificam-web/assets/boot-jingle.s16le \
    /usr/share/wificam-web/assets/boot-jingle.wav
do
    debugfs -R "stat $boot_asset" "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' ||
        die "PegineLab boot melody missing inside ext4: $boot_asset"
done
debugfs -R 'stat /usr/share/wificam-web/cgi-bin/api' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM API is absent from rootfs.ext2"
debugfs -R 'stat /usr/share/wificam-web/cgi-bin/snapshot.jpg' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM snapshot CGI is absent from rootfs.ext2"
debugfs -R 'stat /usr/share/wificam-web/setup/index.html' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM first-boot setup page is absent from rootfs.ext2"
debugfs -R 'stat /usr/share/wificam-web/setup/cgi-bin/claim' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM first-boot claim CGI is absent from rootfs.ext2"
for audio_tool in /usr/bin/rac /usr/sbin/play /usr/sbin/microphone /usr/sbin/speaker; do
    debugfs -R "stat $audio_tool" "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
        die "T23N microphone/speaker tool missing from SD rootfs: $audio_tool"
done
debugfs -R 'stat /usr/sbin/dropbear' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "Dropbear SSH binary is absent from rootfs.ext2"
if ! debugfs -R 'stat /etc/init.d/S30dropbear' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:'; then
    debugfs -R 'stat /etc/init.d/S50dropbear' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
        die "Dropbear init script is absent from rootfs.ext2"
fi

if command -v dumpe2fs >/dev/null 2>&1; then
    ROOTFS_FEATURES="$(dumpe2fs -h "$ROOTFS_EXT" 2>/dev/null | sed -n 's/^Filesystem features:[[:space:]]*//p')"
    case " $ROOTFS_FEATURES " in
      *" 64bit "*|*" metadata_csum "*|*" orphan_file "*)
        die "rootfs.ext2 contains ext4 features unsupported by Linux 3.10: $ROOTFS_FEATURES"
        ;;
    esac
fi

# Use the separately pinned T23N MMC SPL/U-Boot, not the sfcnor U-Boot from
# the 8 MiB SPI image, then assemble a real partitioned SD disk image.
sh "$REPO_DIR/scripts/build_sd_bootloader.sh"

mkdir -p "$IMAGE_DIR"
sh "$REPO_DIR/scripts/assemble_thingino_wificam_sd_image.sh" \
    "$REPO_DIR/out/u-boot-t23n-sd.bin" \
    "$KERNEL_IMAGE" \
    "$ROOTFS_EXT" \
    "$IMAGE_PATH"

IMAGE_SIZE="$(stat -c '%s' "$IMAGE_PATH")"
IMAGE_SHA="$(sha256sum "$IMAGE_PATH" | awk '{print $1}')"

HISTORICAL_REFERENCE="/mnt/d/Thingino/thingino-t23-sd.bin"
HISTORICAL_SHA="not-present"
HISTORICAL_SIZE="not-present"
if [ -f "$HISTORICAL_REFERENCE" ]; then
    HISTORICAL_SHA="$(sha256sum "$HISTORICAL_REFERENCE" | awk '{print $1}')"
    HISTORICAL_SIZE="$(stat -c '%s' "$HISTORICAL_REFERENCE")"
fi

MAX_GITHUB_SIZE=$((95 * 1024 * 1024))
[ "$IMAGE_SIZE" -le "$MAX_GITHUB_SIZE" ] || \
    die "canonical image is $IMAGE_SIZE bytes; refusing Git publish above 95 MiB"

printf '%s  %s\n' "$IMAGE_SHA" "thingino-t23-sd.bin" > "$IMAGE_PATH.sha256"

cat > "$IMAGE_DIR/IMAGE_INFO.txt" <<EOF
PegineLab WIFICAM T23N — canonical Thingino MMC SD candidate

RU:
Профиль-кандидат: $CAMERA
Источник Thingino: $THINGINO_COMMIT
Файл: $IMAGE_PATH
Размер: $IMAGE_SIZE bytes
SHA256: $IMAGE_SHA
Исторический локальный reference: $HISTORICAL_REFERENCE
Reference size: $HISTORICAL_SIZE
Reference SHA256: $HISTORICAL_SHA
Web UI: ОБЯЗАТЕЛЬНО ПРОВЕРЕНА в rootfs.ext2
Web URL после загрузки: http://CAMERA_IP:8090/
Web login: admin / Wificam12345 (0.1_test LAN-only)
SSH: Dropbear TCP 22, обязательный recovery channel
Root: /dev/mmcblk0p2 ext4
Назначение: прямой MMC/SD boot image, НЕ autoupdate payload во SPI.

EN:
Candidate profile: $CAMERA
Thingino source: $THINGINO_COMMIT
File: $IMAGE_PATH
Size: $IMAGE_SIZE bytes
SHA256: $IMAGE_SHA
Historical local reference: $HISTORICAL_REFERENCE
Reference size: $HISTORICAL_SIZE
Reference SHA256: $HISTORICAL_SHA
Web UI: MANDATORY and VERIFIED inside rootfs.ext2
Web URL after boot: http://CAMERA_IP:8090/
Web login: admin / Wificam12345 (0.1_test LAN-only)
SSH: Dropbear TCP 22, mandatory recovery channel
Root: /dev/mmcblk0p2 ext4
Purpose: direct MMC/SD boot image, NOT an SPI autoupdate payload.
EOF

echo
echo "THINGINO WIFICAM SD IMAGE: VERIFIED"
echo "SPI artifact  : $SPI_IMAGE"
echo "Canonical     : $IMAGE_PATH"
echo "Size          : $IMAGE_SIZE bytes"
echo "SHA256        : $IMAGE_SHA"
echo "Historical    : $HISTORICAL_REFERENCE"
echo "Historical SHA: $HISTORICAL_SHA"
echo "Web UI        : FILES VERIFIED inside p2 rootfs.ext2 (CGI execution NOT YET proven)"
echo "Hardware CGI  : PENDING — run scripts/camera_smoke_httpd_cgi.sh on camera"
echo "Security      : S90wificam must refuse port 8090 if CGI source would be exposed"
echo "Web URL       : http://CAMERA_IP:8090/"
echo

if [ "$PUBLISH" = "1" ]; then
    [ "$IMAGE_DIR" = "$REPO_DIR/Thingino" ] || die "private Wi-Fi image cannot be published"
    BRANCH="$(git -C "$REPO_DIR" branch --show-current)"
    [ "$BRANCH" = "mymarrchWFcam" ] || die "refusing publish from branch: $BRANCH"

    git -C "$REPO_DIR" add -f \
        Thingino/thingino-t23-sd.bin \
        Thingino/thingino-t23-sd.bin.sha256 \
        Thingino/IMAGE_INFO.txt

    if git -C "$REPO_DIR" diff --cached --quiet; then
        echo "Git: canonical image already committed."
    else
        git -C "$REPO_DIR" commit -m "firmware(thingino): verify relevant T23N SD image with WIFICAM / проверка релевантного T23N SD образа с WIFICAM"
    fi

    git -C "$REPO_DIR" push origin "$BRANCH"
    echo "Git publish: OK ($BRANCH)"
else
    echo "Not pushed. To build + commit + push in one run:"
    echo "  PUBLISH=1 sh scripts/build_thingino_wificam_image.sh  # only without local/wifi.env"
fi
 "$FINAL_CONFIG" || \
    die "Dropbear SSH is not enabled; local recovery access is mandatory"
grep -Fq "BR2_PACKAGE_BUSYBOX_CONFIG_FRAGMENT_FILES=\"$BUSYBOX_WIFICAM_FRAGMENT\"" "$FINAL_CONFIG" || \
    die "WIFICAM BusyBox fragment path did not reach final Buildroot config"

# FAST builds can reuse an older BusyBox .config from before local.fragment
# selected BusyBox httpd. The config is not "missing" in that case; it is
# stale. Reconfigure BusyBox only when one of the four features actually used
# by PegineLab WIFICAM is absent.
BUSYBOX_REQUIRED_OPTS="
CONFIG_HTTPD
CONFIG_FEATURE_HTTPD_BASIC_AUTH
CONFIG_FEATURE_HTTPD_CGI
CONFIG_WGET
"

busybox_config_path() {
    find "$OUTDIR/build" -path '*/busybox-*/.config' -type f | head -n1
}

BUSYBOX_CONFIG="$(busybox_config_path)"
BUSYBOX_NEEDS_RECONFIGURE=0
if [ -z "$BUSYBOX_CONFIG" ] || [ ! -f "$BUSYBOX_CONFIG" ]; then
    BUSYBOX_NEEDS_RECONFIGURE=1
else
    for opt in $BUSYBOX_REQUIRED_OPTS; do
        grep -q "^$opt=y$" "$BUSYBOX_CONFIG" || BUSYBOX_NEEDS_RECONFIGURE=1
    done
fi

if [ "$BUSYBOX_NEEDS_RECONFIGURE" = "1" ]; then
    echo
    echo "BusyBox HTTP config is stale/incomplete; reconfiguring BusyBox..."
    (
        cd "$THINGINO_DIR"
        env IP= THINGINO_USER_DIR="$USER_ROOT" \
            make CAMERA="$CAMERA" br-busybox-reconfigure
    )
    BUSYBOX_CONFIG="$(busybox_config_path)"
fi

[ -n "$BUSYBOX_CONFIG" ] && [ -f "$BUSYBOX_CONFIG" ] || die "BusyBox .config not found after reconfigure"
for opt in $BUSYBOX_REQUIRED_OPTS; do
    if ! grep -q "^$opt=y$" "$BUSYBOX_CONFIG"; then
        echo "BusyBox HTTP config after reconfigure:" >&2
        grep -E '^(# )?CONFIG_(HTTPD|FEATURE_HTTPD_(CGI|BASIC_AUTH))' "$BUSYBOX_CONFIG" >&2 || true
        die "BusyBox HTTP feature missing after reconfigure: $opt"
    fi
done
if grep -q '^CONFIG_FEATURE_FORCE_APPLETS=y$' "$BUSYBOX_CONFIG"; then
    die "BusyBox FEATURE_FORCE_APPLETS prevents CGI exec; disable it in the fragment"
fi

# A valid BusyBox .config is NOT proof that the cached MIPS binary includes
# CGI. We saw this on the hardware-booted 0.1_test: /cgi-bin/api was served
# literally as "#!/bin/sh", despite the .config checks passing. Force an
# incremental BusyBox rebuild before packaging p2; no kernel rebuild needed.
echo
echo "Rebuilding target BusyBox with CGI options; real execution still requires camera smoke testing..."
(
    cd "$THINGINO_DIR"
    env IP= THINGINO_USER_DIR="$USER_ROOT" \
        make CAMERA="$CAMERA" br-busybox-rebuild
)

# Always regenerate rootfs.ext2 after the BusyBox check.  This guarantees that
# a repaired BusyBox binary and the current WIFICAM overlay are both inside p2.
echo
echo "Generating configured ext4 SD rootfs via Buildroot rootfs-ext2..."
rm -f "$ROOTFS_EXT"
(
    cd "$THINGINO_DIR"
    env IP= THINGINO_USER_DIR="$USER_ROOT" \
        make CAMERA="$CAMERA" rootfs-ext2
)

[ -f "$ROOTFS_EXT" ] || die "rootfs.ext2 missing after rootfs-ext2: $ROOTFS_EXT"
[ -f "$KERNEL_IMAGE" ] || die "uImage missing: $KERNEL_IMAGE"
[ -f "$TARGET/usr/share/wificam-web/index.html" ] || die "WIFICAM index missing from Thingino target rootfs"
[ -x "$TARGET/etc/init.d/S90wificam" ] || die "S90wificam missing/not executable in target rootfs"
[ -x "$TARGET/etc/init.d/S94peginelab-audio" ] ||
    die "PegineLab Raptor boot audio init absent/not executable"
[ -s "$TARGET/usr/share/wificam-web/assets/boot-jingle.s16le" ] ||
    die "PegineLab camera native PCM jingle absent from final rootfs"
[ "$(stat -c '%s' "$TARGET/usr/share/wificam-web/assets/boot-jingle.s16le")" -eq 224000 ] ||
    die "PegineLab camera native PCM jingle has unexpected size"
[ -s "$TARGET/usr/share/wificam-web/assets/boot-jingle.wav" ] ||
    die "PegineLab original WAV jingle absent from final rootfs"

[ -x "$TARGET/usr/share/wificam-web/cgi-bin/api" ] || die "WIFICAM API missing/not executable"
[ -x "$TARGET/usr/share/wificam-web/cgi-bin/snapshot.jpg" ] || die "snapshot CGI missing/not executable"
[ -x "$TARGET/usr/share/wificam-web/cgi-bin/live.mjpg" ] || die "native MJPEG CGI missing/not executable"
[ -x "$TARGET/usr/bin/wificam-ptz-ctl" ] || die "Thingino PTZ controller missing/not executable"
[ -f "$TARGET/usr/share/wificam-web/setup/index.html" ] || die "WIFICAM first-boot setup page missing"
[ -x "$TARGET/usr/share/wificam-web/setup/cgi-bin/claim" ] || die "WIFICAM first-boot claim CGI missing/not executable"
# A voice companion must use this camera's OWN microphone and speaker.
# Shipping RAD without rac/play made the checkbox look functional but the
# speaker cannot output Hombo3 TTS. Ensure each tool reaches final rootfs.
for audio_tool in \
    /usr/bin/rac \
    /usr/sbin/play \
    /usr/sbin/microphone \
    /usr/sbin/speaker
do
    [ -x "$TARGET$audio_tool" ] || die "T23N camera audio tool missing: $audio_tool"
done
[ -x "$TARGET/usr/sbin/dropbear" ] || die "Dropbear binary missing from target rootfs"
if [ ! -x "$TARGET/etc/init.d/S30dropbear" ] && [ ! -x "$TARGET/etc/init.d/S50dropbear" ]; then
    die "Dropbear init script missing from target rootfs"
fi

# If private Wi-Fi provisioning was requested, verify that both the
# Buildroot target and the ACTUAL ext4 image contain the generated config.
# Never print it: the derived WPA2 PSK is password-equivalent.
# Only an explicitly provisioned private build contains a generated WPA2 PSK.
# Ordinary PUBLISH=0 builds under out/candidate-sd have NO local/wifi.env;
# requiring that private file here would make the factory job fail after the
# expensive cross-compilation despite a valid generic SD image.
if [ "$IMAGE_DIR" = "$REPO_DIR/out/private-sd" ]; then
    [ -f "$TARGET/etc/wpa_supplicant.conf" ] || die "private Wi-Fi missing from target"
    grep -q '^# PegineLab: generated locally' "$TARGET/etc/wpa_supplicant.conf" || \
        die "Buildroot overwrote private Wi-Fi target configuration"
    debugfs -R 'cat /etc/wpa_supplicant.conf' "$ROOTFS_EXT" 2>/dev/null | \
        grep -q '^# PegineLab: generated locally' || \
        die "private Wi-Fi config did not reach rootfs.ext2"
    echo "Wi-Fi private config: verified INSIDE rootfs.ext2 (contents hidden)"
fi

grep -q '^WEB_PORT=8090$' "$TARGET/etc/wificam/wificam.conf" || \
    die "WIFICAM WEB_PORT is not 8090"
grep -q '^AUTO_PROVISION_TEST_WEB_AUTH=1$' "$TARGET/etc/wificam/wificam.conf" || \
    die "0.1_test web auth auto-provision is not enabled"
grep -q '^DEFAULT_WEB_USER=admin$' "$TARGET/etc/wificam/wificam.conf" || \
    die "0.1_test default web user mismatch"
grep -q '^DEFAULT_WEB_PASSWORD=Wificam12345$' "$TARGET/etc/wificam/wificam.conf" || \
    die "0.1_test default web password mismatch"
grep -q '^AUTH_PASSWORD_MODE=plain$' "$TARGET/etc/wificam/wificam.conf" || \
    die "0.1_test BusyBox auth compatibility mode is not plain"
grep -q '^SSH_PROTECT=1$' "$TARGET/etc/wificam/wificam.conf" || \
    die "SSH_PROTECT=1 missing from WIFICAM config"
grep -q 'BOOTSTRAP_CONF=' "$TARGET/etc/init.d/S90wificam" || \
    die "S90wificam does not isolate bootstrap httpd config from Thingino"
grep -q 'start_httpd .*BOOTSTRAP_CONF' "$TARGET/etc/init.d/S90wificam" || \
    die "S90wificam bootstrap does not pass a private -c config"
if grep -q 'od -A' "$TARGET/etc/init.d/S90wificam"; then
    die "S90wificam uses BusyBox-incompatible od -A option"
fi
grep -q "printf 'H:%s" "$TARGET/usr/bin/wificam-set-web-password" || \
    die "WIFICAM password helper does not write canonical BusyBox H: webroot"

grep -q 'PegineLab WIFICAM T23N' "$TARGET/usr/share/wificam-web/index.html" || \
    die "wrong Web UI staged in target"
grep -q '^BR2_PACKAGE_THINGINO_KOPT_MMC0_BOOT=y$' "$FINAL_CONFIG" || \
    die "MMC0_BOOT is not enabled in final Thingino config"
grep -q '^BR2_PACKAGE_THINGINO_UBOOT_ROOT="/dev/mmcblk0p2"$' "$FINAL_CONFIG" || \
    die "U-Boot root is not /dev/mmcblk0p2"
grep -q '^BR2_PACKAGE_THINGINO_WEBSERVER_BUSYBOX=y$' "$FINAL_CONFIG" || \
    die "Thingino BusyBox webserver choice is not enabled"

debugfs -R 'stat /usr/share/wificam-web/index.html' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM index is absent from rootfs.ext2"
debugfs -R 'stat /etc/init.d/S90wificam' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "S90wificam is absent from rootfs.ext2"
for boot_asset in \
    /etc/init.d/S94peginelab-audio \
    /usr/share/wificam-web/assets/boot-jingle.s16le \
    /usr/share/wificam-web/assets/boot-jingle.wav
do
    debugfs -R "stat $boot_asset" "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' ||
        die "PegineLab boot melody missing inside ext4: $boot_asset"
done
debugfs -R 'stat /usr/share/wificam-web/cgi-bin/api' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM API is absent from rootfs.ext2"
debugfs -R 'stat /usr/share/wificam-web/cgi-bin/snapshot.jpg' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM snapshot CGI is absent from rootfs.ext2"
debugfs -R 'stat /usr/share/wificam-web/setup/index.html' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM first-boot setup page is absent from rootfs.ext2"
debugfs -R 'stat /usr/share/wificam-web/setup/cgi-bin/claim' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM first-boot claim CGI is absent from rootfs.ext2"
for audio_tool in /usr/bin/rac /usr/sbin/play /usr/sbin/microphone /usr/sbin/speaker; do
    debugfs -R "stat $audio_tool" "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
        die "T23N microphone/speaker tool missing from SD rootfs: $audio_tool"
done
debugfs -R 'stat /usr/sbin/dropbear' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "Dropbear SSH binary is absent from rootfs.ext2"
if ! debugfs -R 'stat /etc/init.d/S30dropbear' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:'; then
    debugfs -R 'stat /etc/init.d/S50dropbear' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
        die "Dropbear init script is absent from rootfs.ext2"
fi

if command -v dumpe2fs >/dev/null 2>&1; then
    ROOTFS_FEATURES="$(dumpe2fs -h "$ROOTFS_EXT" 2>/dev/null | sed -n 's/^Filesystem features:[[:space:]]*//p')"
    case " $ROOTFS_FEATURES " in
      *" 64bit "*|*" metadata_csum "*|*" orphan_file "*)
        die "rootfs.ext2 contains ext4 features unsupported by Linux 3.10: $ROOTFS_FEATURES"
        ;;
    esac
fi

# Use the separately pinned T23N MMC SPL/U-Boot, not the sfcnor U-Boot from
# the 8 MiB SPI image, then assemble a real partitioned SD disk image.
sh "$REPO_DIR/scripts/build_sd_bootloader.sh"

mkdir -p "$IMAGE_DIR"
sh "$REPO_DIR/scripts/assemble_thingino_wificam_sd_image.sh" \
    "$REPO_DIR/out/u-boot-t23n-sd.bin" \
    "$KERNEL_IMAGE" \
    "$ROOTFS_EXT" \
    "$IMAGE_PATH"

IMAGE_SIZE="$(stat -c '%s' "$IMAGE_PATH")"
IMAGE_SHA="$(sha256sum "$IMAGE_PATH" | awk '{print $1}')"

HISTORICAL_REFERENCE="/mnt/d/Thingino/thingino-t23-sd.bin"
HISTORICAL_SHA="not-present"
HISTORICAL_SIZE="not-present"
if [ -f "$HISTORICAL_REFERENCE" ]; then
    HISTORICAL_SHA="$(sha256sum "$HISTORICAL_REFERENCE" | awk '{print $1}')"
    HISTORICAL_SIZE="$(stat -c '%s' "$HISTORICAL_REFERENCE")"
fi

MAX_GITHUB_SIZE=$((95 * 1024 * 1024))
[ "$IMAGE_SIZE" -le "$MAX_GITHUB_SIZE" ] || \
    die "canonical image is $IMAGE_SIZE bytes; refusing Git publish above 95 MiB"

printf '%s  %s\n' "$IMAGE_SHA" "thingino-t23-sd.bin" > "$IMAGE_PATH.sha256"

cat > "$IMAGE_DIR/IMAGE_INFO.txt" <<EOF
PegineLab WIFICAM T23N — canonical Thingino MMC SD candidate

RU:
Профиль-кандидат: $CAMERA
Источник Thingino: $THINGINO_COMMIT
Файл: $IMAGE_PATH
Размер: $IMAGE_SIZE bytes
SHA256: $IMAGE_SHA
Исторический локальный reference: $HISTORICAL_REFERENCE
Reference size: $HISTORICAL_SIZE
Reference SHA256: $HISTORICAL_SHA
Web UI: ОБЯЗАТЕЛЬНО ПРОВЕРЕНА в rootfs.ext2
Web URL после загрузки: http://CAMERA_IP:8090/
Web login: admin / Wificam12345 (0.1_test LAN-only)
SSH: Dropbear TCP 22, обязательный recovery channel
Root: /dev/mmcblk0p2 ext4
Назначение: прямой MMC/SD boot image, НЕ autoupdate payload во SPI.

EN:
Candidate profile: $CAMERA
Thingino source: $THINGINO_COMMIT
File: $IMAGE_PATH
Size: $IMAGE_SIZE bytes
SHA256: $IMAGE_SHA
Historical local reference: $HISTORICAL_REFERENCE
Reference size: $HISTORICAL_SIZE
Reference SHA256: $HISTORICAL_SHA
Web UI: MANDATORY and VERIFIED inside rootfs.ext2
Web URL after boot: http://CAMERA_IP:8090/
Web login: admin / Wificam12345 (0.1_test LAN-only)
SSH: Dropbear TCP 22, mandatory recovery channel
Root: /dev/mmcblk0p2 ext4
Purpose: direct MMC/SD boot image, NOT an SPI autoupdate payload.
EOF

echo
echo "THINGINO WIFICAM SD IMAGE: VERIFIED"
echo "SPI artifact  : $SPI_IMAGE"
echo "Canonical     : $IMAGE_PATH"
echo "Size          : $IMAGE_SIZE bytes"
echo "SHA256        : $IMAGE_SHA"
echo "Historical    : $HISTORICAL_REFERENCE"
echo "Historical SHA: $HISTORICAL_SHA"
echo "Web UI        : FILES VERIFIED inside p2 rootfs.ext2 (CGI execution NOT YET proven)"
echo "Hardware CGI  : PENDING — run scripts/camera_smoke_httpd_cgi.sh on camera"
echo "Security      : S90wificam must refuse port 8090 if CGI source would be exposed"
echo "Web URL       : http://CAMERA_IP:8090/"
echo

if [ "$PUBLISH" = "1" ]; then
    [ "$IMAGE_DIR" = "$REPO_DIR/Thingino" ] || die "private Wi-Fi image cannot be published"
    BRANCH="$(git -C "$REPO_DIR" branch --show-current)"
    [ "$BRANCH" = "mymarrchWFcam" ] || die "refusing publish from branch: $BRANCH"

    git -C "$REPO_DIR" add -f \
        Thingino/thingino-t23-sd.bin \
        Thingino/thingino-t23-sd.bin.sha256 \
        Thingino/IMAGE_INFO.txt

    if git -C "$REPO_DIR" diff --cached --quiet; then
        echo "Git: canonical image already committed."
    else
        git -C "$REPO_DIR" commit -m "firmware(thingino): verify relevant T23N SD image with WIFICAM / проверка релевантного T23N SD образа с WIFICAM"
    fi

    git -C "$REPO_DIR" push origin "$BRANCH"
    echo "Git publish: OK ($BRANCH)"
else
    echo "Not pushed. To build + commit + push in one run:"
    echo "  PUBLISH=1 sh scripts/build_thingino_wificam_image.sh  # only without local/wifi.env"
fi
 "$FINAL_CONFIG" || \
    die "Dropbear SSH is not enabled; local recovery access is mandatory"
# CGI verification is fail-closed on hardware; do not ship a rootfs without
# an HTTP client to perform the local JSON probe.

grep -Fq "BR2_PACKAGE_BUSYBOX_CONFIG_FRAGMENT_FILES=\"$BUSYBOX_WIFICAM_FRAGMENT\"" "$FINAL_CONFIG" || \
    die "WIFICAM BusyBox fragment path did not reach final Buildroot config"

# FAST builds can reuse an older BusyBox .config from before local.fragment
# selected BusyBox httpd. The config is not "missing" in that case; it is
# stale. Reconfigure BusyBox only when one of the four features actually used
# by PegineLab WIFICAM is absent.
BUSYBOX_REQUIRED_OPTS="
CONFIG_HTTPD
CONFIG_FEATURE_HTTPD_BASIC_AUTH
CONFIG_FEATURE_HTTPD_CGI
CONFIG_WGET
"

busybox_config_path() {
    find "$OUTDIR/build" -path '*/busybox-*/.config' -type f | head -n1
}

BUSYBOX_CONFIG="$(busybox_config_path)"
BUSYBOX_NEEDS_RECONFIGURE=0
if [ -z "$BUSYBOX_CONFIG" ] || [ ! -f "$BUSYBOX_CONFIG" ]; then
    BUSYBOX_NEEDS_RECONFIGURE=1
else
    for opt in $BUSYBOX_REQUIRED_OPTS; do
        grep -q "^$opt=y$" "$BUSYBOX_CONFIG" || BUSYBOX_NEEDS_RECONFIGURE=1
    done
fi

if [ "$BUSYBOX_NEEDS_RECONFIGURE" = "1" ]; then
    echo
    echo "BusyBox HTTP config is stale/incomplete; reconfiguring BusyBox..."
    (
        cd "$THINGINO_DIR"
        env IP= THINGINO_USER_DIR="$USER_ROOT" \
            make CAMERA="$CAMERA" br-busybox-reconfigure
    )
    BUSYBOX_CONFIG="$(busybox_config_path)"
fi

[ -n "$BUSYBOX_CONFIG" ] && [ -f "$BUSYBOX_CONFIG" ] || die "BusyBox .config not found after reconfigure"
for opt in $BUSYBOX_REQUIRED_OPTS; do
    if ! grep -q "^$opt=y$" "$BUSYBOX_CONFIG"; then
        echo "BusyBox HTTP config after reconfigure:" >&2
        grep -E '^(# )?CONFIG_(HTTPD|FEATURE_HTTPD_(CGI|BASIC_AUTH))' "$BUSYBOX_CONFIG" >&2 || true
        die "BusyBox HTTP feature missing after reconfigure: $opt"
    fi
done
if grep -q '^CONFIG_FEATURE_FORCE_APPLETS=y$' "$BUSYBOX_CONFIG"; then
    die "BusyBox FEATURE_FORCE_APPLETS prevents CGI exec; disable it in the fragment"
fi

# A valid BusyBox .config is NOT proof that the cached MIPS binary includes
# CGI. We saw this on the hardware-booted 0.1_test: /cgi-bin/api was served
# literally as "#!/bin/sh", despite the .config checks passing. Force an
# incremental BusyBox rebuild before packaging p2; no kernel rebuild needed.
echo
echo "Rebuilding target BusyBox with CGI options; real execution still requires camera smoke testing..."
(
    cd "$THINGINO_DIR"
    env IP= THINGINO_USER_DIR="$USER_ROOT" \
        make CAMERA="$CAMERA" br-busybox-rebuild
)

# Always regenerate rootfs.ext2 after the BusyBox check.  This guarantees that
# a repaired BusyBox binary and the current WIFICAM overlay are both inside p2.
echo
echo "Generating configured ext4 SD rootfs via Buildroot rootfs-ext2..."
rm -f "$ROOTFS_EXT"
(
    cd "$THINGINO_DIR"
    env IP= THINGINO_USER_DIR="$USER_ROOT" \
        make CAMERA="$CAMERA" rootfs-ext2
)

[ -f "$ROOTFS_EXT" ] || die "rootfs.ext2 missing after rootfs-ext2: $ROOTFS_EXT"
[ -f "$KERNEL_IMAGE" ] || die "uImage missing: $KERNEL_IMAGE"
[ -f "$TARGET/usr/share/wificam-web/index.html" ] || die "WIFICAM index missing from Thingino target rootfs"
[ -x "$TARGET/etc/init.d/S90wificam" ] || die "S90wificam missing/not executable in target rootfs"
[ -x "$TARGET/etc/init.d/S94peginelab-audio" ] ||
    die "PegineLab Raptor boot audio init absent/not executable"
[ -s "$TARGET/usr/share/wificam-web/assets/boot-jingle.s16le" ] ||
    die "PegineLab camera native PCM jingle absent from final rootfs"
[ "$(stat -c '%s' "$TARGET/usr/share/wificam-web/assets/boot-jingle.s16le")" -eq 224000 ] ||
    die "PegineLab camera native PCM jingle has unexpected size"
[ -s "$TARGET/usr/share/wificam-web/assets/boot-jingle.wav" ] ||
    die "PegineLab original WAV jingle absent from final rootfs"

[ -x "$TARGET/usr/share/wificam-web/cgi-bin/api" ] || die "WIFICAM API missing/not executable"
[ -x "$TARGET/usr/share/wificam-web/cgi-bin/snapshot.jpg" ] || die "snapshot CGI missing/not executable"
[ -x "$TARGET/usr/share/wificam-web/cgi-bin/live.mjpg" ] || die "native MJPEG CGI missing/not executable"
[ -x "$TARGET/usr/bin/wificam-ptz-ctl" ] || die "Thingino PTZ controller missing/not executable"
[ -f "$TARGET/usr/share/wificam-web/setup/index.html" ] || die "WIFICAM first-boot setup page missing"
[ -x "$TARGET/usr/share/wificam-web/setup/cgi-bin/claim" ] || die "WIFICAM first-boot claim CGI missing/not executable"
# A voice companion must use this camera's OWN microphone and speaker.
# Shipping RAD without rac/play made the checkbox look functional but the
# speaker cannot output Hombo3 TTS. Ensure each tool reaches final rootfs.
for audio_tool in \
    /usr/bin/rac \
    /usr/sbin/play \
    /usr/sbin/microphone \
    /usr/sbin/speaker
do
    [ -x "$TARGET$audio_tool" ] || die "T23N camera audio tool missing: $audio_tool"
done
[ -x "$TARGET/usr/sbin/dropbear" ] || die "Dropbear binary missing from target rootfs"
if [ ! -x "$TARGET/etc/init.d/S30dropbear" ] && [ ! -x "$TARGET/etc/init.d/S50dropbear" ]; then
    die "Dropbear init script missing from target rootfs"
fi

# If private Wi-Fi provisioning was requested, verify that both the
# Buildroot target and the ACTUAL ext4 image contain the generated config.
# Never print it: the derived WPA2 PSK is password-equivalent.
# Only an explicitly provisioned private build contains a generated WPA2 PSK.
# Ordinary PUBLISH=0 builds under out/candidate-sd have NO local/wifi.env;
# requiring that private file here would make the factory job fail after the
# expensive cross-compilation despite a valid generic SD image.
if [ "$IMAGE_DIR" = "$REPO_DIR/out/private-sd" ]; then
    [ -f "$TARGET/etc/wpa_supplicant.conf" ] || die "private Wi-Fi missing from target"
    grep -q '^# PegineLab: generated locally' "$TARGET/etc/wpa_supplicant.conf" || \
        die "Buildroot overwrote private Wi-Fi target configuration"
    debugfs -R 'cat /etc/wpa_supplicant.conf' "$ROOTFS_EXT" 2>/dev/null | \
        grep -q '^# PegineLab: generated locally' || \
        die "private Wi-Fi config did not reach rootfs.ext2"
    echo "Wi-Fi private config: verified INSIDE rootfs.ext2 (contents hidden)"
fi

grep -q '^WEB_PORT=8090$' "$TARGET/etc/wificam/wificam.conf" || \
    die "WIFICAM WEB_PORT is not 8090"
grep -q '^AUTO_PROVISION_TEST_WEB_AUTH=1$' "$TARGET/etc/wificam/wificam.conf" || \
    die "0.1_test web auth auto-provision is not enabled"
grep -q '^DEFAULT_WEB_USER=admin$' "$TARGET/etc/wificam/wificam.conf" || \
    die "0.1_test default web user mismatch"
grep -q '^DEFAULT_WEB_PASSWORD=Wificam12345$' "$TARGET/etc/wificam/wificam.conf" || \
    die "0.1_test default web password mismatch"
grep -q '^AUTH_PASSWORD_MODE=plain$' "$TARGET/etc/wificam/wificam.conf" || \
    die "0.1_test BusyBox auth compatibility mode is not plain"
grep -q '^SSH_PROTECT=1$' "$TARGET/etc/wificam/wificam.conf" || \
    die "SSH_PROTECT=1 missing from WIFICAM config"
grep -q 'BOOTSTRAP_CONF=' "$TARGET/etc/init.d/S90wificam" || \
    die "S90wificam does not isolate bootstrap httpd config from Thingino"
grep -q 'start_httpd .*BOOTSTRAP_CONF' "$TARGET/etc/init.d/S90wificam" || \
    die "S90wificam bootstrap does not pass a private -c config"
if grep -q 'od -A' "$TARGET/etc/init.d/S90wificam"; then
    die "S90wificam uses BusyBox-incompatible od -A option"
fi
grep -q "printf 'H:%s" "$TARGET/usr/bin/wificam-set-web-password" || \
    die "WIFICAM password helper does not write canonical BusyBox H: webroot"

grep -q 'PegineLab WIFICAM T23N' "$TARGET/usr/share/wificam-web/index.html" || \
    die "wrong Web UI staged in target"
grep -q '^BR2_PACKAGE_THINGINO_KOPT_MMC0_BOOT=y$' "$FINAL_CONFIG" || \
    die "MMC0_BOOT is not enabled in final Thingino config"
grep -q '^BR2_PACKAGE_THINGINO_UBOOT_ROOT="/dev/mmcblk0p2"$' "$FINAL_CONFIG" || \
    die "U-Boot root is not /dev/mmcblk0p2"
grep -q '^BR2_PACKAGE_THINGINO_WEBSERVER_BUSYBOX=y$' "$FINAL_CONFIG" || \
    die "Thingino BusyBox webserver choice is not enabled"

debugfs -R 'stat /usr/share/wificam-web/index.html' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM index is absent from rootfs.ext2"
debugfs -R 'stat /etc/init.d/S90wificam' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "S90wificam is absent from rootfs.ext2"
for boot_asset in \
    /etc/init.d/S94peginelab-audio \
    /usr/share/wificam-web/assets/boot-jingle.s16le \
    /usr/share/wificam-web/assets/boot-jingle.wav
do
    debugfs -R "stat $boot_asset" "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' ||
        die "PegineLab boot melody missing inside ext4: $boot_asset"
done
debugfs -R 'stat /usr/share/wificam-web/cgi-bin/api' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM API is absent from rootfs.ext2"
debugfs -R 'stat /usr/share/wificam-web/cgi-bin/snapshot.jpg' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM snapshot CGI is absent from rootfs.ext2"
debugfs -R 'stat /usr/share/wificam-web/setup/index.html' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM first-boot setup page is absent from rootfs.ext2"
debugfs -R 'stat /usr/share/wificam-web/setup/cgi-bin/claim' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "WIFICAM first-boot claim CGI is absent from rootfs.ext2"
for audio_tool in /usr/bin/rac /usr/sbin/play /usr/sbin/microphone /usr/sbin/speaker; do
    debugfs -R "stat $audio_tool" "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
        die "T23N microphone/speaker tool missing from SD rootfs: $audio_tool"
done
debugfs -R 'stat /usr/sbin/dropbear' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
    die "Dropbear SSH binary is absent from rootfs.ext2"
if ! debugfs -R 'stat /etc/init.d/S30dropbear' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:'; then
    debugfs -R 'stat /etc/init.d/S50dropbear' "$ROOTFS_EXT" 2>&1 | grep -q 'Inode:' || \
        die "Dropbear init script is absent from rootfs.ext2"
fi

if command -v dumpe2fs >/dev/null 2>&1; then
    ROOTFS_FEATURES="$(dumpe2fs -h "$ROOTFS_EXT" 2>/dev/null | sed -n 's/^Filesystem features:[[:space:]]*//p')"
    case " $ROOTFS_FEATURES " in
      *" 64bit "*|*" metadata_csum "*|*" orphan_file "*)
        die "rootfs.ext2 contains ext4 features unsupported by Linux 3.10: $ROOTFS_FEATURES"
        ;;
    esac
fi

# Use the separately pinned T23N MMC SPL/U-Boot, not the sfcnor U-Boot from
# the 8 MiB SPI image, then assemble a real partitioned SD disk image.
sh "$REPO_DIR/scripts/build_sd_bootloader.sh"

mkdir -p "$IMAGE_DIR"
sh "$REPO_DIR/scripts/assemble_thingino_wificam_sd_image.sh" \
    "$REPO_DIR/out/u-boot-t23n-sd.bin" \
    "$KERNEL_IMAGE" \
    "$ROOTFS_EXT" \
    "$IMAGE_PATH"

IMAGE_SIZE="$(stat -c '%s' "$IMAGE_PATH")"
IMAGE_SHA="$(sha256sum "$IMAGE_PATH" | awk '{print $1}')"

HISTORICAL_REFERENCE="/mnt/d/Thingino/thingino-t23-sd.bin"
HISTORICAL_SHA="not-present"
HISTORICAL_SIZE="not-present"
if [ -f "$HISTORICAL_REFERENCE" ]; then
    HISTORICAL_SHA="$(sha256sum "$HISTORICAL_REFERENCE" | awk '{print $1}')"
    HISTORICAL_SIZE="$(stat -c '%s' "$HISTORICAL_REFERENCE")"
fi

MAX_GITHUB_SIZE=$((95 * 1024 * 1024))
[ "$IMAGE_SIZE" -le "$MAX_GITHUB_SIZE" ] || \
    die "canonical image is $IMAGE_SIZE bytes; refusing Git publish above 95 MiB"

printf '%s  %s\n' "$IMAGE_SHA" "thingino-t23-sd.bin" > "$IMAGE_PATH.sha256"

cat > "$IMAGE_DIR/IMAGE_INFO.txt" <<EOF
PegineLab WIFICAM T23N — canonical Thingino MMC SD candidate

RU:
Профиль-кандидат: $CAMERA
Источник Thingino: $THINGINO_COMMIT
Файл: $IMAGE_PATH
Размер: $IMAGE_SIZE bytes
SHA256: $IMAGE_SHA
Исторический локальный reference: $HISTORICAL_REFERENCE
Reference size: $HISTORICAL_SIZE
Reference SHA256: $HISTORICAL_SHA
Web UI: ОБЯЗАТЕЛЬНО ПРОВЕРЕНА в rootfs.ext2
Web URL после загрузки: http://CAMERA_IP:8090/
Web login: admin / Wificam12345 (0.1_test LAN-only)
SSH: Dropbear TCP 22, обязательный recovery channel
Root: /dev/mmcblk0p2 ext4
Назначение: прямой MMC/SD boot image, НЕ autoupdate payload во SPI.

EN:
Candidate profile: $CAMERA
Thingino source: $THINGINO_COMMIT
File: $IMAGE_PATH
Size: $IMAGE_SIZE bytes
SHA256: $IMAGE_SHA
Historical local reference: $HISTORICAL_REFERENCE
Reference size: $HISTORICAL_SIZE
Reference SHA256: $HISTORICAL_SHA
Web UI: MANDATORY and VERIFIED inside rootfs.ext2
Web URL after boot: http://CAMERA_IP:8090/
Web login: admin / Wificam12345 (0.1_test LAN-only)
SSH: Dropbear TCP 22, mandatory recovery channel
Root: /dev/mmcblk0p2 ext4
Purpose: direct MMC/SD boot image, NOT an SPI autoupdate payload.
EOF

echo
echo "THINGINO WIFICAM SD IMAGE: VERIFIED"
echo "SPI artifact  : $SPI_IMAGE"
echo "Canonical     : $IMAGE_PATH"
echo "Size          : $IMAGE_SIZE bytes"
echo "SHA256        : $IMAGE_SHA"
echo "Historical    : $HISTORICAL_REFERENCE"
echo "Historical SHA: $HISTORICAL_SHA"
echo "Web UI        : FILES VERIFIED inside p2 rootfs.ext2 (CGI execution NOT YET proven)"
echo "Hardware CGI  : PENDING — run scripts/camera_smoke_httpd_cgi.sh on camera"
echo "Security      : S90wificam must refuse port 8090 if CGI source would be exposed"
echo "Web URL       : http://CAMERA_IP:8090/"
echo

if [ "$PUBLISH" = "1" ]; then
    [ "$IMAGE_DIR" = "$REPO_DIR/Thingino" ] || die "private Wi-Fi image cannot be published"
    BRANCH="$(git -C "$REPO_DIR" branch --show-current)"
    [ "$BRANCH" = "mymarrchWFcam" ] || die "refusing publish from branch: $BRANCH"

    git -C "$REPO_DIR" add -f \
        Thingino/thingino-t23-sd.bin \
        Thingino/thingino-t23-sd.bin.sha256 \
        Thingino/IMAGE_INFO.txt

    if git -C "$REPO_DIR" diff --cached --quiet; then
        echo "Git: canonical image already committed."
    else
        git -C "$REPO_DIR" commit -m "firmware(thingino): verify relevant T23N SD image with WIFICAM / проверка релевантного T23N SD образа с WIFICAM"
    fi

    git -C "$REPO_DIR" push origin "$BRANCH"
    echo "Git publish: OK ($BRANCH)"
else
    echo "Not pushed. To build + commit + push in one run:"
    echo "  PUBLISH=1 sh scripts/build_thingino_wificam_image.sh  # only without local/wifi.env"
fi
