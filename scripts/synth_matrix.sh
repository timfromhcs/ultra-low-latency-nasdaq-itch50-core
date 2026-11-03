#!/usr/bin/env bash
# =============================================================================
# File: scripts/synth_matrix.sh
# Description: Yosys synthesis matrix for 128/256/512-bit variants.
# =============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
for W in 128 256 512; do
  echo "=== DATA_WIDTH=${W} ==="
  scripts/synth_one.sh "${W}"
done
