# OpenLane / LibreLane targets

These are **flow-ready** configurations, not sign-off results. No full P&R run has
been committed, so no Fmax, slack or die-area claim is made.

| File | PDK | Clock target |
|---|---|---|
| `config.json` | legacy Sky130 baseline | 3.10 ns |
| `sky130.json` | Sky130 | 3.10 ns |
| `gf180.json` | GF180MCU | 3.10 ns |
| `ihp-sg13g2.json` | IHP SG13G2 | 3.10 ns |

## Verified toolchain (2026-11-03)

LibreLane **3.0.17** with the `ghcr.io/librelane/librelane:3.0.17` image
(7.52 GB). The built-in smoke test passed end to end: Classic flow **80/80**,
**DRC ✅**, **LVS ✅**, exit code 0.

With Docker Desktop on Windows, run the container directly and keep the PDK in a
named volume (the WSL `--dockerized` path needs Docker integration enabled in the
distro):

```powershell
docker run --rm -v chiplab-librelane-pdk:/root/.volare `
  ghcr.io/librelane/librelane:3.0.17 librelane --smoke-test
```

On a host where the WSL distro has Docker integration, the equivalent is:

```bash
python3 -m pip install --break-system-packages librelane
python3 -m librelane --dockerized --smoke-test     # or: make librelane-smoke
```

## Running this design

```powershell
docker run --rm -v ${PWD}:/work -w /work -v chiplab-librelane-pdk:/root/.volare `
  ghcr.io/librelane/librelane:3.0.17 librelane openlane/sky130.json
```

`dir::../rtl` paths in the config resolve inside the mounted workspace. The parser is
a wide design (484-bit raw record + 512-bit payload), so expect a long run and a large
pin count; the die area in `sky130.json` is a starting point, not a fitted floorplan.

The configurations have **not** been run through the full flow yet; only the smoke
test is verified. Commit only the small JSON/report summaries, never the run
directories (`runs/` and `openlane/runs/` are git-ignored).

The synthesis matrix in `reports/synth_*.log` is a Yosys/ABC cell-count proxy, not an
OpenLane timing report. Do not compare its numbers to a placed-and-routed design.
