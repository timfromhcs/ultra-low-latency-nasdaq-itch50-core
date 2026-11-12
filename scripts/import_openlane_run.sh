#!/usr/bin/env bash
# =============================================================================
# File: scripts/import_openlane_run.sh
# Description: Copy the small evidence files from a LibreLane run directory into
#   openlane/runs/<tag> (git-ignored) so scripts/openlane_summary.mjs can turn
#   them into a committed reports/openlane_<tag>.json. Use after a run finished
#   inside WSL (the heavy GDS/ODB files stay in the WSL filesystem).
# Usage: scripts/import_openlane_run.sh <run-dir> <tag> [out-root]
#   run-dir: e.g. /home/tim/chiplab-native/openlane/runs/native-25fx
#   tag:     e.g. 25fx-full
#   out-root: default /mnt/e/chips/main/openlane/runs
# =============================================================================
set -euo pipefail

RUN=${1:?usage: import_openlane_run.sh <run-dir> <tag> [out-root]}
TAG=${2:?usage: import_openlane_run.sh <run-dir> <tag> [out-root]}
ROOT=${3:-/mnt/e/chips/main/openlane/runs}
OUT="$ROOT/$TAG"

[ -d "$RUN" ] || { echo "[FAIL] no run directory: $RUN" >&2; exit 2; }
[ -f "$RUN/final/metrics.json" ] || { echo "[FAIL] $RUN has no final/metrics.json" >&2; exit 2; }

mkdir -p "$OUT/final" "$OUT/sta" "$OUT/drc"
cp "$RUN/final/metrics.json" "$OUT/final/"
[ -f "$RUN/resolved.json" ] && cp "$RUN/resolved.json" "$OUT/"

# newest STA post-PnR step, if the flow reached it
STA=$(ls -d "$RUN"/*stapostpnr 2>/dev/null | sort -V | tail -1 || true)
if [ -n "${STA}" ]; then
  cp "$STA/summary.rpt" "$OUT/sta/" 2>/dev/null || true
  for corner in "$STA"/max_ss_* "$STA"/min_ff_*; do
    [ -d "$corner" ] || continue
    cp "$corner"/wns.max.rpt "$OUT/sta/" 2>/dev/null || true
    cp "$corner"/max.rpt     "$OUT/sta/" 2>/dev/null || true
    cp "$corner"/wns.min.rpt "$OUT/sta/" 2>/dev/null || true
    cp "$corner"/min.rpt     "$OUT/sta/" 2>/dev/null || true
  done
fi

# DRC reports, wherever those steps ended up
find "$RUN" -path "*magic-drc/reports/drc.magic.rpt" -exec cp {} "$OUT/drc/" \; 2>/dev/null || true
find "$RUN" -path "*klayout-drc/reports/drc.klayout.json" -exec cp {} "$OUT/drc/" \; 2>/dev/null || true

echo "[OK] imported $RUN -> $OUT"
ls -R "$OUT" | head -20
