#!/usr/bin/env bash
# Mirror an extracted beta image tree into backend/static/images/beta/<VERSION>/
# so /images can show every art asset per-beta-version. Run as part of
# process.sh for every ingest, and once manually after a long stretch of
# missed syncs.
#
# Layout matches the per-version CATEGORIES dict in backend/app/routers/images.py:
#   backend/static/images/beta/<VERSION>/cards/      <- flattened card_portraits
#   backend/static/images/beta/<VERSION>/monsters/   <- monsters/
#   backend/static/images/beta/<VERSION>/misc/       <- ancients + backgrounds
#   backend/static/images/beta/<VERSION>/ui/         <- ui/ (recursive)
#   backend/static/images/beta/<VERSION>/vfx/        <- vfx/ (recursive)
#   backend/static/images/beta/latest -> v<VERSION>  (symlink, updated atomically)
#
# Usage:
#   VERSION=v0.106.0 ./sync-images.sh                            # default extraction dir
#   VERSION=v0.105.1 EXTRACT_DIR=/tmp/scratch/images ./sync-images.sh
#
# Idempotent — rsync --delete prunes anything Mega Crit cut between
# extractions, so beta/v0.106.0/cards/ never carries v0.105.x relic
# portraits that v0.106 removed.

set -euo pipefail

REPO="${SPIRE_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
VERSION="${VERSION:-}"
EXTRACT="${EXTRACT_DIR:-$REPO/extraction/beta/raw/images}"

if [ -z "$VERSION" ]; then
  echo "VERSION env var required (e.g. v0.106.0)"
  exit 1
fi
case "$VERSION" in
  v*) ;;
  *) echo "VERSION must start with 'v' (got: $VERSION)"; exit 1 ;;
esac

if [ ! -d "$EXTRACT" ]; then
  echo "extraction missing at $EXTRACT — run process.sh first"
  exit 1
fi

DEST="$REPO/backend/static/images/beta/$VERSION"
LATEST_LINK="$REPO/backend/static/images/beta/latest"
mkdir -p "$DEST"

# rsync filter: include images, exclude Godot import metadata + Mac dupes.
RSYNC_FILTER=(
  --include='*.png'
  --include='*.webp'
  --include='*.jpg'
  --include='*.gif'
  --include='*/'                # follow directories
  --exclude='*.png.import'
  --exclude='*.import'
  --exclude='*.tpsheet'
  --exclude='* [0-9].png'       # Mac Finder dupes: "abrasive 2.png"
  --exclude='* [0-9].webp'
  --exclude='* [0-9]'           # Mac Finder dupe dirs: "cards 2"
  --exclude='*'                  # exclude everything else
)

echo "==> syncing $VERSION into $DEST"

echo "==> cards: flattening card_portraits/**/*.png into $VERSION/cards/"
rm -rf "$DEST/cards" && mkdir -p "$DEST/cards"
find "$EXTRACT/packed/card_portraits" -name '*.png' ! -name '*.import' -type f 2>/dev/null | while IFS= read -r src; do
  name=$(basename "$src")
  case "$name" in
    beta.png|ancient_beta.png) continue ;;
  esac
  cp "$src" "$DEST/cards/$name"
done
echo "    cards: $(find "$DEST/cards" -name '*.png' | wc -l | tr -d ' ') files"

echo "==> monsters: copying monsters/ into $VERSION/monsters/"
mkdir -p "$DEST/monsters"
rsync -a --delete "${RSYNC_FILTER[@]}" "$EXTRACT/monsters/" "$DEST/monsters/"
echo "    monsters: $(find "$DEST/monsters" -name '*.png' | wc -l | tr -d ' ') files"

echo "==> misc: copying ancients/ + map/ into $VERSION/misc/"
rm -rf "$DEST/misc" && mkdir -p "$DEST/misc"
rsync -a "${RSYNC_FILTER[@]}" "$EXTRACT/ancients/" "$DEST/misc/" 2>/dev/null || true
if [ -d "$EXTRACT/map" ]; then
  rsync -a "${RSYNC_FILTER[@]}" "$EXTRACT/map/" "$DEST/misc/" 2>/dev/null || true
fi
echo "    misc: $(find "$DEST/misc" -name '*.png' | wc -l | tr -d ' ') files"

echo "==> ui: copying ui/ tree into $VERSION/ui/"
mkdir -p "$DEST/ui"
rsync -a --delete "${RSYNC_FILTER[@]}" "$EXTRACT/ui/" "$DEST/ui/"
echo "    ui: $(find "$DEST/ui" -name '*.png' | wc -l | tr -d ' ') files"

echo "==> vfx: copying vfx/ tree into $VERSION/vfx/"
mkdir -p "$DEST/vfx"
rsync -a --delete "${RSYNC_FILTER[@]}" "$EXTRACT/vfx/" "$DEST/vfx/"
echo "    vfx: $(find "$DEST/vfx" -name '*.png' | wc -l | tr -d ' ') files"

# Atomically swing the `latest` symlink to this version. ln -sfn replaces
# an existing symlink without leaving a window where it points at nothing.
echo "==> updating latest -> $VERSION"
ln -sfn "$VERSION" "$LATEST_LINK"

echo "==> done"
