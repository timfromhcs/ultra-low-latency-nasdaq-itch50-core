# Contributing

## Ground rules

1. **No unverified claims.** Every benchmark or latency number in a README/PR must link
   to a report or a command that reproduces it.
2. **Never weaken a test to make it pass.** Add a regression first.
3. **Keep the interfaces documented.** Changes to `itch_top.sv`, the canonical 80-byte
   record or the `/api/*` JSON update `docs/architecture.md`, `llms-full.txt` and the
   web/backend decoders in the same commit.
4. **Licence.** Contributions are accepted under the repository's PolyForm Small Business
   terms. Do not copy GPL code into the RTL or WASM.

## Local setup

```bash
# RTL (Linux/WSL)
sudo apt-get install verilator yosys iverilog z3 cvc5
python3 -m pip install cocotb pytest scapy

# WASM / web / backend
rustup target add wasm32-unknown-unknown
npm install
python -m pip install build
```

## Gates

```bash
make lint
python tb/itch_model.py --count 100000 --out tb/vectors
make sim
./formal/run_formal.sh z3
python -m pytest -q tb/test_model.py
node scripts/wasm_smoke.mjs && python scripts/check_wasm_fixture.py
node backend/run.mjs --compare --count 100000
node mcp/client_smoke.mjs
node scripts/build_vercel.mjs && node scripts/test_vercel_api.mjs
```

Deep gate: 1M vectors + `make sim` + `formal/solver_matrix.sh` + synthesis matrix.

## Pull requests

- One logical change per PR.
- Include the exact command and result in the description.
- Screenshots for UI changes at 390 and 1440 px.
- Update `CHANGELOG.md`.
