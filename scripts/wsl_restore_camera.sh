#!/bin/sh
# Recovery installer: do not delete/overwrite old projects or wipe output.
set -eu
ROOT="$HOME/myipcam"
REPO="$ROOT/wificam_T23N"
BRANCH=mymarrchWFcam
URL=https://github.com/musikfed/wificam_T23N.git
mkdir -p "$ROOT"
if [ ! -e "$REPO" ]; then
    git clone --branch "$BRANCH" "$URL" "$REPO"
else
    if [ ! -d "$REPO/.git" ]; then
        echo "ERROR: $REPO exists but is not a Git checkout; preserve it and inspect manually" >&2
        exit 1
    fi
    REMOTE="$(git -C "$REPO" remote get-url origin)"
    case "$REMOTE" in
        "https://github.com/musikfed/wificam_T23N.git"|"https://github.com/musikfed/wificam_T23N"|"git@github.com:musikfed/wificam_T23N.git") ;;
        *) echo "ERROR: unexpected origin: $REMOTE; refusing to modify old checkout" >&2; exit 1 ;;
    esac
    if [ -n "$(git -C "$REPO" status --porcelain)" ]; then
        echo "ERROR: local WIFICAM changes/untracked files exist; preserve them before pull" >&2
        git -C "$REPO" status --short
        exit 1
    fi
    git -C "$REPO" fetch origin "$BRANCH"
    git -C "$REPO" switch "$BRANCH"
    git -C "$REPO" merge --ff-only "origin/$BRANCH"
fi
echo "WIFICAM checkout ready at: $REPO"
git -C "$REPO" status --short --branch
echo "Thingino will be cloned automatically at the pinned commit by build script if absent."
echo "No old directories were deleted. Review unused copies, THEN archive or remove manually."
