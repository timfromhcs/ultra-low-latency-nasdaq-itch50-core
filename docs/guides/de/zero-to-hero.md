# Zero to Hero — ChipLab in 20 Minuten

Dieser Leitfaden führt vom frischen Clone bis zur laufenden WebGPU-Demo, zum formalen
Beweis und zur Single-EXE. Alles läuft lokal auf deiner Maschine.

## 1. Demo starten

```bash
git clone https://github.com/timfromhcs/ultra-low-latency-nasdaq-itch50-core.git
cd ultra-low-latency-nasdaq-itch50-core
node backend/server.mjs
```

Öffne <http://127.0.0.1:4173>. Wähle **ITCH-50 v2**, 100.000 Nachrichten, drücke
**Run feed**. Erwartet: `41,29` Gbps, `0` Fehler, Tape, Depth-Density und Latenz-Balken.

Zeigt das GPU-Badge **CPU fallback**, funktioniert die Demo trotzdem: Der Parser ist
WASM, Canvas2D zeichnet dieselben Bins. WebGPU beschleunigt nur die Visualisierung.

## 2. Zahlen lesen

- **Throughput** ist die Modell-Line-Rate bei 322,26 MHz, kein Wanduhr-Benchmark.
- **Latency** ist das Chip-Modell: 1 Takt ab dem Window-Register; echtes
  Wire-to-Output ist 2 Takte, weil der Ingress-Register davor liegt.
- **Errors** vergleicht jeden Record mit dem Golden-Parser. Der **lossy**-Chip ist die
  Negativkontrolle und muss bei Compare FAIL zeigen.

## 3. Einen Record prüfen

```bash
python tb/itch_model.py --count 1000 --out tb/vectors_small
python - <<'PY'
import sys; sys.path.insert(0, "tb")
import itch_model as m
s = open("tb/vectors_small/stream.bin", "rb").read()
r = m.parse_stream(s)
print(len(r), "Records")
print(r[0])
PY
```

Das Python-Modell ist die ausführbare Spezifikation. RTL, Rust/WASM und Browser
erzeugen denselben 80-Byte-Record.

## 4. Volle Verifikation (Linux/WSL)

```bash
sudo apt-get install -y verilator yosys iverilog z3 cvc5 python3-pip
python3 -m pip install cocotb pytest scapy

make lint
python tb/itch_model.py --count 100000 --out tb/vectors
make sim
formal/run_formal.sh z3
formal/solver_matrix.sh
python -m pytest -q tb/test_model.py
```

Erwartet: `0` Mismatches, Formal `PASSED`, alle Unit-Tests grün. Der 1M-Lauf ist das
Deep-Gate; die CI nutzt eine kleinere Zahl wegen der Laufzeit.

## 5. Single EXE bauen

```bash
npm install
npm run build:exe
dist\chiplab.exe --port 4190
```

Die EXE enthält Web-App und 50-KB-WASM. Sie öffnet den Browser und serviert dieselben
`/api/*`-Endpunkte. Auf dem Zielrechner ist keine Node-Installation nötig.

## 6. Docker und Vercel

```bash
docker compose up --build          # http://localhost:4173
node scripts/build_vercel.mjs      # public/ + api/ für Vercel
```

Der Vercel-Build ist static-first. Der Run-Verlauf bleibt im Browser (OPFS); `/api/*`
ist zustandslose Compute-Funktion. Absicht: Deine Daten bleiben lokal.

## 7. Pakete und MCP

```bash
node mcp/client_smoke.mjs                    # MCP-Handshake + 5 Tools
cd packages/npm && npm pack                  # @chiplab/core
cd packages/python && python -m build        # chiplab-itch
```

## 8. Was noch offen ist

- Multi-Frame-MoldUDP64-Backpressure (Single-Frame-Beweis ist grün).
- OpenLane/OpenSTA-Fmax-Sign-off; 322 MHz ist ein Modellziel.
- RTL-Top-of-Book (das WASM-Modell hat eines).
- Veröffentlichte npm/PyPI/GHCR-Artefakte (Tokens nötig).

Wenn etwas fehlschlägt: `node scripts/autonomy.mjs` ausführen und
`reports/autonomy.log` lesen; der Lauf startet das nächste Gate und protokolliert den
exakten Befehl.
