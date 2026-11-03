# Zero to hero — ChipLab in 20 minutes

This guide takes you from a fresh clone to a running WebGPU lab, a formal proof and a
single-file executable. Everything runs on your machine.

## 1. Run the demo

```bash
git clone https://github.com/timfromhcs/ultra-low-latency-nasdaq-itch50-core.git
cd ultra-low-latency-nasdaq-itch50-core
node backend/server.mjs
```

Open <http://127.0.0.1:4173>. Pick **ITCH-50 v2**, 100,000 messages, press **Run feed**.
You should see `41.29` Gbps, `0` errors, a tape, a depth density and a latency bar.

If the GPU badge says **CPU fallback**, the demo still works: the parser is WASM, and
Canvas2D draws the same bins. WebGPU only accelerates the visual aggregation.

## 2. Read the numbers

- **Throughput** is the model line rate at 322.26 MHz, not a wall-clock benchmark.
- **Latency** is the chip model: 1 cycle from the window register; the true wire-to-output
  path is 2 cycles because the ingress register is in front of it.
- **Errors** compares every record to the golden parser. The **lossy** chip is a
  negative control and must show FAIL in Compare.

## 3. Verify one record

```bash
python tb/itch_model.py --count 1000 --out tb/vectors_small
python - <<'PY'
import sys; sys.path.insert(0, "tb")
import itch_model as m
s = open("tb/vectors_small/stream.bin", "rb").read()
r = m.parse_stream(s)
print(len(r), "records")
print(r[0])
PY
```

The Python model is the executable specification. The RTL, Rust/WASM and browser all
produce the same 80-byte canonical record.

## 4. Run the full verification (Linux/WSL)

```bash
sudo apt-get install -y verilator yosys iverilog z3 cvc5 python3-pip
python3 -m pip install cocotb pytest scapy

make lint
python tb/itch_model.py --count 100000 --out tb/vectors
make sim                 # full-field Verilator regression
formal/run_formal.sh z3  # BMC + k-induction + covers
formal/solver_matrix.sh  # records each available solver
python -m pytest -q tb/test_model.py
```

Expected: `0` mismatches, formal `PASSED`, all unit tests green. The 1M run is the
deep gate; the CI uses a smaller count for time.

## 5. Build the single EXE

```bash
npm install
npm run build:exe
dist\chiplab.exe --port 4190
dist\chiplab.exe --host 0.0.0.0 --port 4173 --token "long-token"
```

The EXE embeds the web app and the 50 KB WASM. It opens the browser and serves the same
`/api/*` endpoints plus the local cloud. No Node installation is needed on the target
machine.

## 5b. Local cloud (v0.3.0)

```bash
node backend/server.mjs --host 0.0.0.0 --token "long-token"
# prints the LAN URL, e.g. http://192.168.1.20:4173
```

Open that URL on a phone on the same network, paste the token into the **Local cloud**
panel and press **Test**, then **Sync** or **Pull**. Runs are stored as JSON under
`.data/` on your machine. Without `--token`, only loopback clients may write.

## 6. Docker and Vercel

```bash
docker build -t chiplab:0.3.0 .
docker run --rm -p 4173:4173 -e CHIPLAB_TOKEN=long-token chiplab:0.3.0
node scripts/build_vercel.mjs      # public/ + api/ for Vercel
```

The Vercel build is static-first. Run history stays in the browser (OPFS); `/api/*` is
stateless compute only. This is deliberate: your data is local by default. Docker writes
need `CHIPLAB_TOKEN` because requests arrive from a non-loopback bridge address.

## 7. Packages and MCP

```bash
node mcp/client_smoke.mjs                    # MCP handshake + 12 tools
cd packages/npm && npm pack                  # @chiplab/core
cd packages/python && python -m build        # chiplab-itch
```

## 8. What is still open

- Multi-frame MoldUDP64 backpressure (single-frame proof passes).
- OpenLane/OpenSTA Fmax sign-off; the 322 MHz number is a model target.
- RTL top-of-book (the WASM model has one).
- Published npm/PyPI/GHCR artifacts (tokens required).

If something fails, run `node scripts/autonomy.mjs` and read
`reports/autonomy.log`; it runs the next gate and records the exact command.
