#!/bin/sh
# READ ONLY: Acer WSL camera project inventory. Prints no Wi-Fi passwords.
set -u
printf '\n=== WSL camera inventory (read-only) ===\n'
printf 'User: '; id -un
printf 'Home: %s\n' "$HOME"
uname -a
df -h "$HOME" 2>/dev/null
for d in "$HOME/myipcam" "$HOME/myipcam/wificam_T23N" "$HOME/myipcam/thingino-firmware" "$HOME/thingino-firmware" "/mnt/d/Thingino"; do
    if [ -d "$d" ]; then
        echo "PRESENT: $d"
        if [ -d "$d/.git" ]; then
            echo "  git status (no changes):"
            git -C "$d" status --short --branch 2>/dev/null | head -n 20
            git -C "$d" remote -v 2>/dev/null | sed -n '1,2p'
        fi
    else
        echo "MISSING: $d"
    fi
done
echo "=== Existing SD image candidates (read-only) ==="
for dir in "$HOME/myipcam" /mnt/d/Thingino; do
    [ -d "$dir" ] || continue
    find "$dir" -maxdepth 6 -type f -name 'thingino-t23-sd.bin' \
        -printf '%p %s bytes\n' 2>/dev/null
done
echo "=== Current block devices (read-only; DO NOT infer SD device yet) ==="
lsblk -o NAME,PATH,SIZE,MODEL,TRAN,RM,FSTYPE,MOUNTPOINTS 2>/dev/null
echo "=== Device passthrough ==="
command -v lsusb >/dev/null 2>&1 && lsusb || true
echo "Done. NOTHING deleted, overwritten, cloned or flashed."
