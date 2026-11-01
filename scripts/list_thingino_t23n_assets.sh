#!/bin/sh
set -eu

command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not installed" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not installed" >&2; exit 1; }

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT INT TERM

curl -fsSL --retry 3 --connect-timeout 20 \
  https://api.github.com/repos/themactep/thingino-firmware/releases/latest \
  -o "$TMP"

python3 - "$TMP" "$@" <<'PY'
import json
import sys

path = sys.argv[1]
filters = [x.lower() for x in sys.argv[2:]]

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

names = []
for asset in data.get("assets", []):
    name = asset.get("name", "")
    low = name.lower()
    if not (low.startswith("thingino-") and "t23n" in low and low.endswith(".bin")):
        continue
    if all(term in low for term in filters):
        names.append(name)

print(f"Thingino latest release: {data.get('tag_name', '?')}")
print(f"T23N assets matched    : {len(names)}")
print()
for name in sorted(names):
    print(name)

if not names:
    print("No matching T23N release assets.")
    sys.exit(1)
PY
