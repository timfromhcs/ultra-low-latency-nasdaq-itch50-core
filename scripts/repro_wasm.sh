#!/usr/bin/env bash
# =============================================================================
# File: scripts/repro_wasm.sh
# Description: Reproducible-build check for the WASM core. Builds the crate
#   twice into separate clean target dirs with the same toolchain and compares
#   SHA-256. Also reports whether the committed web/wasm binary matches.
#   Writes reports/repro_wasm.json. Requires the wasm32-unknown-unknown target.
# =============================================================================
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

OUT="reports/repro_wasm.json"
mkdir -p reports

sha() { sha256sum "$1" | cut -d' ' -f1; }

build() {
  local dir="$1"
  rm -rf "$dir"
  ( cd wasm-core && CARGO_TARGET_DIR="$dir" cargo build --target wasm32-unknown-unknown --release --locked >/dev/null 2>&1 ) || return 1
  echo "$dir/wasm32-unknown-unknown/release/chiplab_core.wasm"
}

echo "[REPRO] build A"
A="$(build /tmp/repro_wasm_a)" || { echo "[FAIL] build A"; exit 1; }
echo "[REPRO] build B"
B="$(build /tmp/repro_wasm_b)" || { echo "[FAIL] build B"; exit 1; }

HA="$(sha "$A")"
HB="$(sha "$B")"
COMMITTED="web/wasm/chiplab_core.wasm"
HC="unknown"
[ -f "$COMMITTED" ] && HC="$(sha "$COMMITTED")"

RUSTC="$(rustc --version | cut -d' ' -f2)"
CARGO="$(cargo --version | cut -d' ' -f2)"
SIZE_A="$(stat -c%s "$A")"

STATUS="PASS"
[ "$HA" = "$HB" ] || STATUS="FAIL"

cat > "$OUT" <<EOF
{
  "generatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "rustc": "${RUSTC}",
  "cargo": "${CARGO}",
  "buildA": "${HA}",
  "buildB": "${HB}",
  "bytes": ${SIZE_A},
  "committed": "${HC}",
  "matchesCommitted": $([ "$HA" = "$HC" ] && echo true || echo false),
  "status": "${STATUS}"
}
EOF

echo "[REPRO] A=${HA}"
echo "[REPRO] B=${HB}"
echo "[REPRO] committed=${HC}"
echo "[REPRO] ${STATUS} (${SIZE_A} bytes, rustc ${RUSTC})"
[ "$STATUS" = "PASS" ] || exit 1
