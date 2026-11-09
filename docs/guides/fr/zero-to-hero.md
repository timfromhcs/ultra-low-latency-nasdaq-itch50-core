# Zero to Hero — ChipLab en 20 minutes

Ce guide va du clone frais au laboratoire WebGPU, à la preuve formelle et à l'EXE
mono-fichier. Tout tourne sur votre machine.

## 1. Lancer la démo

```bash
git clone https://github.com/timfromhcs/ultra-low-latency-nasdaq-itch50-core.git
cd ultra-low-latency-nasdaq-itch50-core
node backend/server.mjs
```

Ouvrez <http://127.0.0.1:4173>. Choisissez **ITCH-50 v2**, 100 000 messages, cliquez
sur **Run feed**. Attendu : `41,29` Gbps, `0` erreur, un tape, une densité de carnet
et un histogramme de latence.

Si le badge GPU indique **CPU fallback**, la démo fonctionne quand même : le parseur est
en WASM et Canvas2D dessine les mêmes bins. WebGPU n'accélère que l'agrégation visuelle.

## 2. Lire les chiffres

- **Throughput** est le débit modèle à 322,26 MHz, pas un benchmark horloge murale.
- **Latency** est le modèle du chip : 1 cycle depuis le registre de fenêtre ; le vrai
  trajet wire-to-output est de 2 cycles, car le registre d'entrée précède.
- **Errors** compare chaque enregistrement au parseur doré. Le chip **lossy** est le
  contrôle négatif et doit afficher FAIL dans Compare.

## 3. Vérifier un enregistrement

```bash
python tb/itch_model.py --count 1000 --out tb/vectors_small
python - <<'PY'
import sys; sys.path.insert(0, "tb")
import itch_model as m
s = open("tb/vectors_small/stream.bin", "rb").read()
r = m.parse_stream(s)
print(len(r), "enregistrements")
print(r[0])
PY
```

Le modèle Python est la spécification exécutable. Le RTL, Rust/WASM et le navigateur
produisent le même enregistrement canonique de 80 octets.

## 4. Vérification complète (Linux/WSL)

```bash
sudo apt-get install -y verilator yosys iverilog z3 cvc5 python3-pip
python3 -m pip install cocotb pytest scapy

make lint
node scripts/gate.mjs    # 11 vérifications portables (modèle, WASM, MCP, cloud, liens docs, ...)
python tb/itch_model.py --count 100000 --out tb/vectors
make sim
formal/run_formal.sh z3
formal/solver_matrix.sh
python -m pytest -q tb/test_model.py
```

Attendu : `0` mismatch, formel `PASSED`, tous les tests verts. Le run 1M est la porte
profonde ; la CI utilise un compte plus petit pour le temps.

## 5. Construire l'EXE unique

```bash
npm install
npm run build:exe
dist\chiplab.exe --port 4190
dist\chiplab.exe --host 0.0.0.0 --port 4173 --token "jeton-long"
```

L'EXE embarque l'application web et le WASM de 50 Ko. Il ouvre le navigateur et sert les
mêmes endpoints `/api/*` plus le cloud local. Aucune installation de Node n'est
nécessaire sur la cible.

## 5b. Cloud local (v0.3.1)

```bash
node backend/server.mjs --host 0.0.0.0 --token "jeton-long"
# affiche l'URL LAN, par ex. http://192.168.1.20:4173
```

Ouvrez cette URL sur un téléphone du même réseau, collez le jeton dans le panneau
**Local cloud**, puis **Test**, **Sync** ou **Pull**. Les runs sont stockés en JSON sous
`.data/`. Sans `--token`, seuls les clients loopback peuvent écrire.

## 6. Docker et Vercel

```bash
docker build -t chiplab:0.3.1 .
docker run --rm -p 4173:4173 -e CHIPLAB_TOKEN=jeton-long chiplab:0.3.1
node scripts/build_vercel.mjs      # public/ + api/ pour Vercel
```

Le build Vercel est static-first. L'historique reste dans le navigateur (OPFS) ;
`/api/*` est un calcul sans état. C'est volontaire : vos données restent locales. Les
écritures Docker exigent `CHIPLAB_TOKEN`, car les requêtes viennent d'un pont non-loopback.

## 7. Paquets et MCP

```bash
node mcp/client_smoke.mjs                    # handshake MCP + 12 outils
cd packages/npm && npm pack                  # @chiplab/core
cd packages/python && python -m build        # chiplab-itch
```

## 8. Ce qui reste ouvert

- Sign-off physique : la STA Sky130 pre-PnR est publiée (WNS −9,14 ns à 3,10 ns,
  Fmax ≈81 MHz), mais le placement/routage demande une planification d'horloge et un
  floorplan ajusté. Aucun sign-off DRC/LVS ou timing n'existe.
- Cible FPGA (UltraScale+/Agilex avec MAC 100G) et intégration PCIe/DMA.
- Exécution complète du harnais Caravel ; le wrapper de forme Caravel et le chemin
  Wishbone sont testés.
- Publication npm/PyPI : les étapes opt-in existent, mais la configuration OIDC côté
  registre manque. Les assets GitHub Release fonctionnent aujourd'hui.
- Pas de silicium fabriqué ; tout ici est de la preuve RTL, simulation et pre-PnR.

## 9. Pour aller plus loin

- [Datasheet](../../datasheet.md) — ports, cibles de timing, STA pre-PnR mesurée
- [Carte des registres](../../register-map.md) — host, Wishbone, Caravel, snapshot, compteurs
- [Guide d'intégration](../../integration-guide.md) — câblage et démarrage
- [Errata](../../errata.md) — limites connues, en clair
- [Référence API](../../api.md) — HTTP, MCP, npm et Python

En cas d'échec : `node scripts/autonomy.mjs` puis lire `reports/autonomy.log` ; il lance
la prochaine porte et journalise la commande exacte.
