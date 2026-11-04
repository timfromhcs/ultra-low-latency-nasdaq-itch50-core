#!/usr/bin/env bash
# =============================================================================
# File: scripts/normalize_sdist.sh
# Description: Rewrite a setuptools sdist deterministically: fixed member order,
#   fixed mtime (SOURCE_DATE_EPOCH), numeric owner/group, gzip without name or
#   timestamp. The content is unchanged; only the container metadata is fixed.
#   Usage: scripts/normalize_sdist.sh <in.tar.gz> <out.tar.gz>
# =============================================================================
set -euo pipefail

IN="$1"
OUT="$2"
EPOCH="${SOURCE_DATE_EPOCH:-1700000000}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

tar xzf "$IN" -C "$TMP"
top="$(ls -1 "$TMP")"
tar --sort=name --mtime="@${EPOCH}" --owner=0 --group=0 --numeric-owner \
    -cf "$TMP/out.tar" -C "$TMP" "$top"
gzip -n -9 -c "$TMP/out.tar" > "$OUT"
echo "[normalize] $IN -> $OUT (epoch $EPOCH)"
