#!/usr/bin/env bash
# =============================================================================
# File: formal/solver_matrix.sh
# Description: Run the v2 formal proof with every SMT solver available and
#              write a machine-readable report. Requires at least one PASS.
# =============================================================================
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT}/reports"
mkdir -p "${OUT}"
REPORT="${OUT}/formal.json"
TMP="$(mktemp)"
echo "[" > "${TMP}"
first=1
pass=0
for S in z3 cvc5 boolector bitwuzla yices yices-smt2; do
  if ! command -v "${S}" >/dev/null 2>&1; then
    continue
  fi
  echo "[solver] ${S}"
  start=$(date +%s)
  if "${ROOT}/formal/run_formal.sh" "${S}" > "${OUT}/formal_${S}.log" 2>&1; then
    status="PASS"; pass=$((pass+1))
  else
    status="FAIL"
  fi
  end=$(date +%s)
  if [ "${first}" -eq 0 ]; then echo "," >> "${TMP}"; fi
  first=0
  printf '  {"solver":"%s","status":"%s","seconds":%s,"log":"reports/formal_%s.log"}' \
    "${S}" "${status}" "$((end-start))" "${S}" >> "${TMP}"
done
echo "]" >> "${TMP}"
cat "${TMP}" > "${REPORT}"
rm -f "${TMP}"
echo "[solver] passes: ${pass}"
cat "${REPORT}"
[ "${pass}" -ge 1 ]
