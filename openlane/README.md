# OpenLane / LibreLane targets

These are **flow-ready** configurations, not sign-off results. No full P&R run has
been committed, so no Fmax, slack or die-area claim is made.

| File | PDK | Clock target |
|---|---|---|
| `config.json` | legacy Sky130 baseline | 3.10 ns |
| `sky130.json` | Sky130 | 3.10 ns |
| `sky130_250mhz.json` | Sky130 | 4.00 ns (250 MHz) |
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

## Measured pre-PnR STA (2026-11-03)

`OpenROAD.STAPrePNR`, sky130_fd_sc_hd, ss/100C/1.60 V, 19,936 instances
(199,739 µm²):

| Clock | Setup WNS | Setup TNS | Fmax estimate |
|---|---|---|---|
| 4.00 ns (250 MHz) | **−8.27 ns** | −22,463 ns | **81.47 MHz** |
| 3.10 ns (322 MHz) | **−9.14 ns** | −25,193 ns | ≈81.6 MHz |
| 3.10 ns, GF180 (ss/125 °C) | **−19.87 ns** | — | **43.54 MHz** |
| 3.10 ns, IHP SG13G2 (slow/125 °C) | **−3.08 ns** | — | **161.9 MHz** |
| 3.10 ns, wrapper (ss/100 °C) | **−8.62 ns** | — | **85.34 MHz** |

IHP also shows a small hold violation (WNS −0.052 ns). All values are pre-PnR. The
wrapper (`itch_host_wrap`, 32-bit host port instead of the debug bus) removes the
`raw_payload` endpoint from the critical path; the worst path is now FF → FF.

Worst path in both: a shifter-counter flip-flop → `raw_payload[0]` (the asynchronous
bypass output). The limit is the bypass/decoder combinational cone, not the pipeline
depth. **Pre-PnR only — no placement/routing, no sign-off.**

Reproduce the 250 MHz STA-only run:

```powershell
docker run --rm -v ${PWD}:/work -w /work -v chiplab-librelane-ciel:/root/.ciel `
  ghcr.io/librelane/librelane:3.0.17 `
  librelane --run-tag sky130-250mhz-sta --to OpenROAD.STAPrePNR openlane/sky130_250mhz.json
node scripts/openlane_summary.mjs openlane/runs/sky130-250mhz-sta
```

## Full-flow attempts (best effort, no success claim)

| Attempt | Result |
|---|---|
| 3.10 ns, all steps | Post-CTS resizer (`OpenROAD.ResizerTimingPostCTS`) ran >1 h on the −9.14 ns path without progress; killed. |
| 3.10 ns, resizer steps skipped | Reached **GlobalRouting**, which **failed with congestion** (GRT-0116) at the 700×700 µm die with the full 1,100-pin interface (484-bit `raw_order_data`, 512-bit `raw_payload`, …). |
| wrapper, 700 µm | Same GRT-0116 congestion at GlobalRouting (clock net with 1,533 terminals, ~20k cells). |
| wrapper, 1400 µm, 40 % density | GlobalPlacement **diverged** (GPL-0305, invalid step length); RePlAce is numerically unstable with this clock fanout. |

The pin count and the unbuffered 1,533-terminal clock, not the standard-cell area, are
the blockers. A physical run needs a designed floorplan/pin plan and clock planning
(e.g. clock buffers inserted before placement, a fitted die), which is follow-up work.
**No P&R, DRC or LVS result exists for this design.**

## Running this design

```powershell
docker run --rm -v ${PWD}:/work -w /work -v chiplab-librelane-ciel:/root/.ciel `
  ghcr.io/librelane/librelane:3.0.17 librelane openlane/sky130.json
```

`dir::../rtl` paths in the config resolve inside the mounted workspace. The parser is
a wide design (484-bit raw record + 512-bit payload), so expect a long run and a large
pin count; the die area in `sky130.json` is a starting point, not a fitted floorplan.

Only the smoke test and the pre-PnR STA runs are verified; the full flow has not
completed (see above). Commit only the small JSON/report summaries, never the run
directories (`runs/` and `openlane/runs/` are git-ignored).

After a run, extract the small summary:

```bash
node scripts/openlane_summary.mjs                 # newest run
node scripts/openlane_summary.mjs openlane/runs/chiplab-sky130
```

It writes `reports/openlane_<tag>.json` (die/core bbox, instances, area, setup/hold,
DRC/LVS) and prints the same numbers. When `resolved.json` has `CLOCK_PERIOD` and the
setup slack is negative, it also derives an Fmax estimate (`1000 / (T - WNS)`) and a
`timingClosed` flag. That file is the only artifact to commit.

The synthesis matrix in `reports/synth_*.log` is a Yosys/ABC cell-count proxy, not an
OpenLane timing report. Do not compare its numbers to a placed-and-routed design.
