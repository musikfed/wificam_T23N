#!/bin/sh
set -eu

REPO="musikfed/wificam_T23N"
TAG="0.1_test"
TARGET="release/0.1_test"
TITLE="PegineLab WIFICAM T23 SD — 0.1_test"
IMAGE="Thingino/thingino-t23-sd.bin"
SHA_FILE="Thingino/thingino-t23-sd.bin.sha256"
NOTES="Thingino/RELEASE_0.1_test.md"
EXPECTED_SHA="f9f50a8595d4fe629ed787483188319000d2780bd3c6dee56fef4de5e754f6be"

command -v gh >/dev/null 2>&1 || {
    echo "ERROR: GitHub CLI (gh) is not installed." >&2
    echo "Ubuntu/WSL: sudo apt update && sudo apt install -y gh" >&2
    exit 1
}

gh auth status >/dev/null 2>&1 || {
    echo "ERROR: gh is not authenticated." >&2
    echo "Run: gh auth login" >&2
    exit 1
}

[ -f "$IMAGE" ] || { echo "ERROR: missing $IMAGE" >&2; exit 1; }
[ -f "$SHA_FILE" ] || { echo "ERROR: missing $SHA_FILE" >&2; exit 1; }
[ -f "$NOTES" ] || { echo "ERROR: missing $NOTES" >&2; exit 1; }

actual="$(sha256sum "$IMAGE" | awk '{print $1}')"
[ "$actual" = "$EXPECTED_SHA" ] || {
    echo "ERROR: firmware SHA256 mismatch" >&2
    echo "expected: $EXPECTED_SHA" >&2
    echo "actual  : $actual" >&2
    exit 1
}

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "Release $TAG already exists:"
    gh release view "$TAG" --repo "$REPO" --web
    exit 0
fi

echo "Creating GitHub prerelease $TAG from $TARGET ..."
gh release create "$TAG"     "$IMAGE"     "$SHA_FILE"     --repo "$REPO"     --target "$TARGET"     --title "$TITLE"     --notes-file "$NOTES"     --prerelease

echo
echo "RELEASE CREATED:"
gh release view "$TAG" --repo "$REPO" --json url,tagName,name,isPrerelease
