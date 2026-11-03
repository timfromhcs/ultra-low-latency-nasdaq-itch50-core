# OpenLane targets

These are **flow-ready** configurations, not sign-off results. No P&R run has been
committed, so no Fmax, slack or die-area claim is made.

| File | PDK | Clock target |
|---|---|---|
| `config.json` | legacy Sky130 baseline | 3.10 ns |
| `sky130.json` | Sky130 | 3.10 ns |
| `gf180.json` | GF180MCU | 3.10 ns |
| `ihp-sg13g2.json` | IHP SG13G2 | 3.10 ns |

Run with OpenLane/LibreLane in Docker/WSL, then commit only the small JSON/report files:

```bash
openlane --pdk-root <pdk> openlane/sky130.json
```

The synthesis matrix in `reports/synth_*.log` is a Yosys/ABC cell-count proxy, not an
OpenLane timing report. Do not compare its numbers to a placed-and-routed design.
