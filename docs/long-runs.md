# Long LibreLane runs: resume, diagnose, clean up

Practical notes from the actual runs in this repository. Read `openlane/README.md` for
the measured results; this page is about operating the flow.

---

## 1. Environment

- LibreLane **3.0.17** image: `ghcr.io/librelane/librelane:3.0.17`.
- Docker Desktop on Windows; the WSL `--dockerized` mode needs Docker integration in
  the distro, so run the container directly.
- Keep the PDK in a named volume and mount it at **`/root/.ciel`** (LibreLane 3 uses
  CIEL, not `.volare`):

```powershell
docker run --rm -v ${PWD}:/work -w /work -v chiplab-librelane-ciel:/root/.ciel `
  ghcr.io/librelane/librelane:3.0.17 `
  librelane --run-tag <tag> openlane/<config>.json
```

The first run downloads the PDK into the volume; later runs reuse it.

## 2. Bounded runs first

Before a full flow, run only synthesis + pre-PnR STA (minutes):

```powershell
... librelane --run-tag <tag>-sta --to OpenROAD.STAPrePNR openlane/<config>.json
node scripts/openlane_summary.mjs openlane/runs/<tag>-sta
```

The summary tolerates LibreLane's `Infinity`/`NaN` metrics and prints WNS/TNS,
instances/area, DRC/LVS and an Fmax estimate.

## 3. Full flow and the knobs that matter

```powershell
... librelane --run-tag <tag>-full `
  --skip OpenROAD.ResizerTimingPostCTS --skip OpenROAD.ResizerTimingPostGRT `
  openlane/<config>.json
```

- The resizer can spend hours on a design that is far from closure; skipping it gets
  you routing/DRC/LVS evidence instead of a timing number.
- `GRT_ALLOW_CONGESTION: 1` turns the GRT-0116 abort into a warning so the flow can
  reach detailed routing.
- `RUN_HEURISTIC_DIODE_INSERTION: false` drops `Odb.HeuristicDiodeInsertion` — the
  step that hit `GRT-0183` (heap underflow) on the congested wrapper run. In 3.0.17 the
  switch is `RUN_HEURISTIC_DIODE_INSERTION`; `RUN_ANTENNA_REPAIR` gates
  `OpenROAD.RepairAntennas` (checked in the installed package, not guessed). Passing
  `--skip` for a step that a switch already removed fails with "no step(s) with ID".
- `RUN_ANTENNA_REPAIR: false` removes the repair step too, but then the design is not
  antenna-clean: report antenna/DRC findings honestly.
- `CTS_BALANCE_LEVELS` is **obsolete** in 3.0.17 (CTS-0132, ignored); do not use it as
  the clock-planning knob. `CTS_SINK_CLUSTERING_ENABLE`, `CTS_CLK_BUFFER_LIST`,
  `CTS_MAX_CAP` and `CTS_MAX_SLEW` are the effective ones.
- `GRT_OVERFLOW_ITERS` is the run-time switch nobody expects: on the 32-bit wrapper
  (54 k instances, 1400 µm die) 33 iterations took ≈1 h, so the 200 used in the first
  fitted attempt implied a >6 h global-routing phase. Keep evidence runs at 20–30;
  `GRT_ALLOW_CONGESTION: 1` lets the flow continue to detailed routing anyway.

## 4. Resuming a killed run

LibreLane can continue an existing run tag, but the CLI still requires a config:

```powershell
... librelane --last-run openlane/<same-config>.json `
  --skip OpenROAD.ResizerTimingPostCTS --skip OpenROAD.ResizerTimingPostGRT
```

`--last-run` picks the newest run directory under `openlane/runs`. Repeat the same
`--skip` flags: skipped steps are not recorded as completed, so omitting them re-runs
those steps.

Observed on 2026-11-10: Docker Desktop restarted while `OpenROAD.GlobalRouting` was
running (container exit 255). The `--last-run` resume re-ran the flow from synthesis
(new step directories from `44-yosys-synthesis` upward) instead of continuing at the
failed routing step, so budget the replay time. Check `flow.log` for the current step
number instead of assuming an exact resume point.

A host/Docker restart kills the container (`unexpected EOF`); check `docker ps`, start
Docker Desktop, then resume. Long runs (many hours) are not reliable on a machine that
reboots; prefer the bounded runs and the small-block validation.

## 5. Known failure modes

| Symptom | Meaning | Action |
|---|---|---|
| `GRT-0116` congestion | not routable at this die/density | larger die, lower `PL_TARGET_DENSITY_PCT`, or `GRT_ALLOW_CONGESTION` |
| `GPL-0305` RePlAce diverged | placement numerics/density | different density, smaller die, fewer pins |
| `DPL-0036` detailed placement failed | too many pins for the die perimeter | larger die or narrower interface |
| `GRT-0183` heap underflow in DiodeInsertion | antenna repair on a congested net | disable antenna repair for evidence-only runs |
| container `unexpected EOF` | host/Docker restart | resume with `--last-run` |

## 6. Clean up

- Run directories are git-ignored (`runs/`, `openlane/runs/`) and can be several GB.
  Keep the runs referenced by `reports/openlane_*.json`; delete the failed ones.
- Commit only the small report:

```bash
node scripts/openlane_summary.mjs openlane/runs/<tag>
```

## 7. Reporting rule

A completed flow is evidence for **that block and configuration only**. The parser has
no completed P&R/DRC/LVS; the `itch_metrics` block does. Never turn one into a claim
about the other, and never call pre-PnR STA a sign-off.
