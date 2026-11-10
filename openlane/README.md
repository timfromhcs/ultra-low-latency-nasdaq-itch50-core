# OpenLane / LibreLane targets

These are **flow-ready** configurations, not sign-off results. Only the pre-PnR STA
runs and the small-block validation are measured; the parser has no completed P&R, so
no parser Fmax, slack or die-area claim is made. Operating notes (resume, knobs,
failure modes, cleanup): [`../docs/long-runs.md`](../docs/long-runs.md).

| File | Target | PDK | Clock |
|---|---|---|---|
| `config.json` | parser (legacy baseline) | Sky130 | 3.10 ns |
| `sky130.json` | parser | Sky130 | 3.10 ns |
| `sky130_250mhz.json` | parser, STA only | Sky130 | 4.00 ns (250 MHz) |
| `gf180.json` | parser, STA only | GF180MCU | 3.10 ns |
| `ihp-sg13g2.json` | parser, STA only | IHP SG13G2 | 3.10 ns |
| `sky130_wrap.json` | `itch_host_wrap` (128-bit) | Sky130 | 3.10 ns |
| `sky130_wrap32.json` | `itch_wishbone_wrap` (32-bit) | Sky130 | 3.10 ns |
| `sky130_wrap32_big.json` | 32-bit wrapper, congestion allowed | Sky130 | 3.10 ns |
| `sky130_wrap32_100mhz.json` | 32-bit wrapper at 100 MHz, relaxed flow | Sky130 | 10.0 ns |
| `sky130_wrap32_fitted.json` | 32-bit wrapper, 1400 µm die at 25 % density, antenna-diode step off, 10 ns | Sky130 | 10.0 ns |
| `sky130_wrap32_fitted_area.json` | 32-bit wrapper, AREA synthesis variant (routing experiments only) | Sky130 | 10.0 ns |
| `sky130_wrap32_wide.json` | 32-bit wrapper, 1800 µm die at 15 %, `CTS_APPLY_NDR: "none"`, antenna repair off | Sky130 | 10.0 ns |
| `sky130_metrics.json` | `itch_metrics` (small-block flow validation) | Sky130 | 3.10 ns |

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

**Native WSL path (2026-11-10):** the image's Nix closure is unpacked into `/nix` and
the Sky130 PDK into `/opt/ciel`, so `librelane --pdk-root /opt/ciel` runs without
Docker and survives the Docker Desktop VM restarts that kill containers. Parity checked:
the native STA of `sky130_wrap32_fitted.json` reproduced the container result exactly
(setup WNS **+0.3537 ns**, **19,660** max-slew violations). Recipe:
[`../docs/long-runs.md`](../docs/long-runs.md) §2b.

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
| 3.10 ns, wrapper 32-bit ingress | **−6.55 ns** | — | **103.67 MHz** |

IHP also shows a small hold violation (WNS −0.052 ns). All values are pre-PnR. The
wrapper (`itch_host_wrap`, 32-bit host port instead of the debug bus) removes the
`raw_payload` endpoint from the critical path; the worst path is now FF → FF.

Worst path in both: a shifter-counter flip-flop → `raw_payload[0]` (the asynchronous
bypass output). The limit is the bypass/decoder combinational cone, not the pipeline
depth. **Pre-PnR only — no placement/routing, no sign-off.**

## Fitted wrapper attempt (2026-11-10) — measured, incomplete

`openlane/sky130_wrap32_fitted.json` (32-bit wrapper, 1400 µm die, 25 % density,
`RUN_HEURISTIC_DIODE_INSERTION: false`, 10 ns) was run to characterise the congestion
blocker. Numbers below are measured; **there is still no completed P&R for the parser**.

| Stage | Result |
|---|---|
| Pre-PnR STA (ss/100 °C/1.60 V) | setup **+0.354 ns** (clean), hold clean, **19,660 max-slew violations** |
| Post-CTS | 54,569 instances (15,779 combinational, 1,565 FFs, 6,236 timing-repair buffers, 435 clock buffers, 26,302 tap cells), 19.2 % utilization |
| Global routing | 33 of the allowed 200 overflow iterations in ≈1 h in Docker; native build does 6 clock-NDR passes in ≈55 min. **Final congestion: 81.26 % total usage, 25,661 overflowed nodes** (met1 85.0 %, met2 90.6 %, met3 73.2 %, met4 69.8 %, met5 53.0 %) |

The AREA-synthesis variant (`sky130_wrap32_fitted_area.json`, 133,125 µm² chip area)
routes much more easily but is **not timing-viable**: setup WNS **−83.06 ns** at 10 ns
with 4,286 violations. The 10 ns closure of the DELAY netlist is therefore
buffer-driven, and its congestion comes from that buffer volume plus the wide buses.

Detailed routing on that die confirmed the congestion: **64,091 violations** after the
first pass and **264,817** in optimisation iteration 1 (10–20 %, ≈14 min/iteration), so
the run was abandoned instead of burning hours. `sky130_wrap32_wide.json` (1800 µm,
15 %, `CTS_APPLY_NDR: "none"`, antenna repair off) is the follow-up attempt.

The wide die fixed global routing — **1 overflow node, 45.9 % usage, no NDR retries** —
but detailed routing still ended at **171,735 violations**, dominated by **met1 shorts
(82,017)** and **met2 shorts (65,698)**; the 1400 µm run had the same short signature
(264,817). Die size is therefore not the remaining blocker; the next investigation is
the per-net distribution of those shorts (wide internal buses / pin access).

Two container kills (`exit 255`) happened while GlobalRouting ran; each coincided with a
Docker Desktop VM restart (init logs at ≈45 min intervals). `.wslconfig` was capped at
`memory=6GB`/`processors=6`; raising it to 10 GB/8 CPUs (same swap) gave the container
9.7 GiB instead of 5.8 GiB, but a third VM restart still killed the run with the
container at only 1.2 GiB — so the restarts are not a container OOM (the original cap
was restored). Long LibreLane runs
remain unreliable on this host; see [`../docs/long-runs.md`](../docs/long-runs.md).

Reproduce the 250 MHz STA-only run:

```powershell
docker run --rm -v ${PWD}:/work -w /work -v chiplab-librelane-ciel:/root/.ciel `
  ghcr.io/librelane/librelane:3.0.17 `
  librelane --run-tag sky130-250mhz-sta --to OpenROAD.STAPrePNR openlane/sky130_250mhz.json
node scripts/openlane_summary.mjs openlane/runs/sky130-250mhz-sta
```

## Small-block full-flow validation (2026-11-09)

`openlane/sky130_metrics.json` targets the `itch_metrics` block at a **10 ns** clock.
This is a flow/DRC/LVS validation, not a speed claim for the parser. The complete
Classic flow finished:

| Result | Value |
|---|---|
| Standard cells | 6,776 (456 sequential), 42,127 µm² cell area |
| Die | 500 × 500 µm (not fitted) |
| Routing DRC | **0** (iterations 1/2/3: 1 → 0) |
| Magic DRC / KLayout DRC | **0 / 0** |
| LVS | **0 errors** (devices, nets, pins, properties) |
| Timing | closed at 10 ns, WNS ≈ +0.12 ns, Fmax estimate ≈ 101 MHz |
| CTS | 107 clock buffers + 9 clock inverters; 300 hold buffers |

Two earlier attempts failed: a 200 µm die could not place (~400 top-level pins on an
800 µm perimeter, DPL-0036) and at 3.10 ns the resizer did not converge. Artifact:
`reports/openlane_metrics-full3.json`.

## Full-flow attempts (best effort, no success claim)

| Attempt | Result |
|---|---|
| 3.10 ns, all steps | Post-CTS resizer (`OpenROAD.ResizerTimingPostCTS`) ran >1 h on the −9.14 ns path without progress; killed. |
| 3.10 ns, resizer steps skipped | Reached **GlobalRouting**, which **failed with congestion** (GRT-0116) at the 700×700 µm die with the full 1,100-pin interface (484-bit `raw_order_data`, 512-bit `raw_payload`, …). |
| wrapper, 700 µm | Same GRT-0116 congestion at GlobalRouting (clock net with 1,533 terminals, ~20k cells). |
| wrapper, 1400 µm, 40 % density | GlobalPlacement **diverged** (GPL-0305, invalid step length); RePlAce is numerically unstable with this clock fanout. |
| wrapper, 1400 µm, 50 % density, timing-driven placement off | GlobalPlacement **diverged again** (GPL-0305). Three configurations fail in three different places; this needs clock planning and a real floorplan, not config tweaks. |
| wrapper 32-bit, 700 µm | GlobalRouting **still congested** (GRT-0116) even with the narrow interface; clock fanout is 1,566 terminals. |
| wrapper 32-bit, 1500 µm, 25 %, 10 ns, no skips | Placement, CTS and resizer ran; GlobalRouting finished with congestion (warning), then **`OpenROAD.DiodeInsertion` failed** with `GRT-0183` (heap underflow in 3D maze routing) after ~7 h. |
| wrapper 32-bit, 1500 µm, 10 ns, antenna repair off, resizer/diode skipped | GlobalRouting ran without antenna loops but the **container died** ("unexpected EOF" at GRT 32/50, host/Docker restart), so no result. Long P&R runs are not reliable in this environment. |
| wrapper 32-bit, 1000 µm, 35 % density, congestion allowed | Passed GlobalRouting, entered **DetailedRouting**; violations fell from ~695k to ~148k but the run did not converge and was stopped by a host restart. No DRC/LVS result. |

The **unbuffered ~1,566-terminal clock** and placement density, not the pin count (the
32-bit wrapper with ~80 pins still congested), are the blockers. A physical run needs
clock planning (clock buffers before placement) and a fitted floorplan/pin plan, which
is follow-up work. **No P&R, DRC or LVS result exists for this design.**

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
