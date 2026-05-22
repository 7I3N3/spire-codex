#!/usr/bin/env bash
# One-shot script: walks every archived .pck under extraction/beta/archives/,
# extracts each into a scratch dir, runs sync-images.sh with the right
# VERSION, then tears the scratch down. End state is
# backend/static/images/beta/<version>/{cards,monsters,misc,ui,vfx} for
# every beta we have an archive for.
#
# Used once after #327 lands. Future beta drops go through process.sh →
# sync-images directly and don't need this.
#
# Usage:
#   ./tools/beta-watch/backfill-images.sh           # all archives
#   VERSIONS="v0.103.0 v0.104.0" ./tools/beta-watch/backfill-images.sh   # subset
#
# Pre-req: Godot RE Tools.app available at the canonical install path.

set -euo pipefail

REPO="${SPIRE_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
GDRE="${GDRE:-/Applications/Godot RE Tools.app/Contents/MacOS/Godot RE Tools}"
SYNC="$REPO/tools/beta-watch/sync-images.sh"
SCRATCH_ROOT="${SCRATCH_ROOT:-/tmp/spire-codex-backfill}"

[ -x "$GDRE" ] || { echo "Godot RE Tools not found at $GDRE"; exit 1; }
[ -x "$SYNC" ] || { echo "sync-images.sh not found at $SYNC"; exit 1; }

# If VERSIONS unset, derive from archives on disk.
if [ -z "${VERSIONS:-}" ]; then
  VERSIONS=$(ls -1 "$REPO/extraction/beta/archives/"sts2-v*.pck 2>/dev/null \
             | sed -E 's:.*/sts2-(v[^.]+\.[0-9]+\.[0-9]+)\.pck:\1:' \
             | sort -V \
             | tr '\n' ' ')
fi

if [ -z "$VERSIONS" ]; then
  echo "no archives found in $REPO/extraction/beta/archives/"
  exit 1
fi

echo "backfilling: $VERSIONS"

for V in $VERSIONS; do
  PCK="$REPO/extraction/beta/archives/sts2-${V}.pck"
  if [ ! -f "$PCK" ]; then
    echo "==> $V: archive missing ($PCK), skipping"
    continue
  fi

  TARGET="$REPO/backend/static/images/beta/$V"
  if [ -d "$TARGET" ] && [ -n "$(ls -A "$TARGET" 2>/dev/null)" ]; then
    echo "==> $V: already populated at $TARGET, skipping (rm -rf it to force)"
    continue
  fi

  SCRATCH="$SCRATCH_ROOT/$V"
  echo "==> $V: extracting to $SCRATCH"
  rm -rf "$SCRATCH" && mkdir -p "$SCRATCH"
  "$GDRE" --headless "--recover=$PCK" "--output=$SCRATCH" 2>&1 | tail -3

  if [ ! -d "$SCRATCH/images" ]; then
    echo "==> $V: extraction produced no images/ dir, skipping"
    rm -rf "$SCRATCH"
    continue
  fi

  echo "==> $V: syncing images"
  VERSION="$V" EXTRACT_DIR="$SCRATCH/images" "$SYNC"

  echo "==> $V: cleaning scratch"
  rm -rf "$SCRATCH"
done

# Restore latest symlink to whatever's actually newest — backfill marches
# through old versions and `ln -sfn` inside sync-images.sh keeps pointing
# `latest` at whatever it just synced, so the final iteration wins. If
# we backfilled older versions after v0.106.0, force latest forward.
NEWEST=$(ls -1d "$REPO/backend/static/images/beta/"v*/ 2>/dev/null \
         | sed 's:/$::' | xargs -n1 basename | sort -V | tail -1)
if [ -n "$NEWEST" ]; then
  ln -sfn "$NEWEST" "$REPO/backend/static/images/beta/latest"
  echo "==> latest -> $NEWEST"
fi

echo "==> backfill complete"
