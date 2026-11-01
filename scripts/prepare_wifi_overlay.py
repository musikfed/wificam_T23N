#!/usr/bin/env python3
"""Embed a local-only WPA2-Personal configuration into the SD rootfs overlay.

The LOCAL Wi-Fi file is deliberately NOT a sourced shell script.
Only exact JSON quoted key/value strings are accepted. No SSID/password
or derived PSK is written to stdout; no third-party Python modules needed.

Thingino S38wpa_supplicant reads /etc/wpa_supplicant.conf before trying
its captive portal, so an already-configured rootfs can join the LAN.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import stat
import sys


class WifiConfigError(ValueError):
    pass


def read_config(path: Path) -> tuple[str, str]:
    if path.is_symlink() or not path.is_file():
        raise WifiConfigError("Local Wi-Fi config must be a regular file, not a symlink")
    if stat.S_IMODE(path.stat().st_mode) & 0o077:
        raise WifiConfigError("local/wifi.env must be private (chmod 600 local/wifi.env)")
    values: dict[str, str] = {}
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        name, sep, raw = line.partition("=")
        name = name.strip()
        if not sep or name not in ("WIFI_SSID", "WIFI_PASSWORD") or name in values:
            raise WifiConfigError(f"Invalid/duplicate local Wi-Fi key on line {line_no}")
        try:
            value = json.loads(raw.strip())
        except (ValueError, TypeError) as exc:
            raise WifiConfigError(f"Value on line {line_no} must be a JSON quoted string") from exc
        if not isinstance(value, str) or "\n" in value or "\r" in value or "\0" in value:
            raise WifiConfigError(f"Invalid Wi-Fi value on line {line_no}")
        values[name] = value
    if set(values) != {"WIFI_SSID", "WIFI_PASSWORD"}:
        raise WifiConfigError("Expected WIFI_SSID and WIFI_PASSWORD")
    ssid, password = values["WIFI_SSID"], values["WIFI_PASSWORD"]
    ssid_bytes = ssid.encode("utf-8")
    password_bytes = password.encode("utf-8")
    if not (1 <= len(ssid_bytes) <= 32):
        raise WifiConfigError("SSID length must be 1-32 UTF-8 bytes")
    if not (8 <= len(password_bytes) <= 63):
        raise WifiConfigError("WPA2 password length must be 8-63 UTF-8 bytes")
    if any(not (32 <= v <= 126) for v in password_bytes):
        raise WifiConfigError("Password must use printable ASCII bytes for WPA2 compatibility")
    return ssid, password


def build_wpa_conf(ssid: str, password: str) -> bytes:
    # Supplicant accepts hex SSID, avoiding all quoting/injection corner cases.
    # WPA2 PSK is PBKDF2-HMAC-SHA1(passphrase, SSID, 4096, 32).
    ssid_bytes = ssid.encode("utf-8")
    psk = hashlib.pbkdf2_hmac("sha1", password.encode("utf-8"), ssid_bytes, 4096, 32).hex()
    return (
        "# PegineLab: generated locally; this file grants access to your Wi-Fi.\n"
        "# Do not publish the resulting SD image or rootfs.\n"
        "ctrl_interface=/run/wpa_supplicant\n"
        "update_config=0\n"
        "ap_scan=1\n"
        "network={\n"
        f"    ssid={ssid_bytes.hex()}\n"
        "    key_mgmt=WPA-PSK\n"
        "    proto=RSN\n"
        "    pairwise=CCMP\n"
        f"    psk={psk}\n"
        "    scan_ssid=1\n"
        "}\n"
    ).encode("ascii")


def prepare(local_file: Path, overlay: Path) -> bool:
    if not local_file.exists() and not local_file.is_symlink():
        return False
    ssid, password = read_config(local_file)
    dest = overlay / "etc/wpa_supplicant.conf"
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_name(dest.name + ".wificam.tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(build_wpa_conf(ssid, password))
        os.replace(tmp, dest)
        os.chmod(dest, 0o600)
    finally:
        if tmp.exists():
            tmp.unlink()
    # No SSID, passphrase, or PSK echoed into CI/build logs.
    return True


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: prepare_wifi_overlay.py LOCAL_WIFI_ENV ROOTFS_OVERLAY", file=sys.stderr)
        return 2
    try:
        if prepare(Path(sys.argv[1]), Path(sys.argv[2])):
            print("Wi-Fi: PRIVATE WPA2 config staged in rootfs overlay; do NOT publish image")
        else:
            print("Wi-Fi: no local config; Thingino stock portal remains available")
    except (WifiConfigError, OSError, UnicodeError) as exc:
        print(f"ERROR: Wi-Fi preparation failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
