#!/usr/bin/env bash
# =============================================================================
# File: scripts/repro_python.sh
# Description: Reproducible-build check for the Python package. Builds the wheel
#   and sdist twice with SOURCE_DATE_EPOCH, normalizes the sdist container, and
#   compares SHA-256. Writes reports/repro_python.json.
# =============================================================================
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
EPOCH="${SOURCE_DATE_EPOCH:-1700000000}"
export SOURCE_DATE_EPOCH="$EPOCH"
SRC="$ROOT/packages/python"
A=/tmp/repro_py_a
B=/tmp/repro_py_b
OUT="reports/repro_python.json"
mkdir -p reports

rm -rf "$A" "$B"
( cd /tmp && python3 -m build --wheel --sdist --outdir "$A" "$SRC" >/dev/null 2>&1 ) || { echo "[FAIL] build A"; exit 1; }
( cd /tmp && python3 -m build --wheel --sdist --outdir "$B" "$SRC" >/dev/null 2>&1 ) || { echo "[FAIL] build B"; exit 1; }

wa=$(ls "$A"/*.whl); wb=$(ls "$B"/*.whl)
sa=$(ls "$A"/*.tar.gz); sb=$(ls "$B"/*.tar.gz)

# Deterministic sdist containers, compared in a separate directory so the
# original build outputs stay untouched.
mkdir -p "$A/norm" "$B/norm"
./scripts/normalize_sdist.sh "$sa" "$A/norm/$(basename "$sa")" >/dev/null
./scripts/normalize_sdist.sh "$sb" "$B/norm/$(basename "$sb")" >/dev/null

h() { sha256sum "$1" | cut -d' ' -f1; }
WHA=$(h "$wa"); WHB=$(h "$wb")
SHA=$(h "$A/norm/$(basename "$sa")"); SHB=$(h "$B/norm/$(basename "$sb")")

STATUS=PASS
[ "$WHA" = "$WHB" ] || STATUS=FAIL
[ "$SHA" = "$SHB" ] || STATUS=FAIL

cat > "$OUT" <<EOF
{
  "generatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "sourceDateEpoch": ${EPOCH},
  "python": "$(python3 --version | cut -d' ' -f2)",
  "wheel": { "buildA": "${WHA}", "buildB": "${WHB}", "same": $([ "$WHA" = "$WHB" ] && echo true || echo false) },
  "sdist": { "buildA": "${SHA}", "buildB": "${SHB}", "same": $([ "$SHA" = "$SHB" ] && echo true || echo false), "normalized": true },
  "status": "${STATUS}"
}
EOF

echo "[REPRO] wheel A=${WHA}"
echo "[REPRO] wheel B=${WHB}"
echo "[REPRO] sdist A=${SHA}"
echo "[REPRO] sdist B=${SHB}"
echo "[REPRO] ${STATUS}"
[ "$STATUS" = "PASS" ] || exit 1
