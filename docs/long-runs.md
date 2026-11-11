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

## 2b. Native LibreLane in WSL (survives Docker VM restarts)

Docker Desktop on this host restarts its VM every ~40–50 min and kills running
containers (`exit 255`), which makes multi-hour routing runs impossible. The same
LibreLane build can be run natively inside WSL Ubuntu, without Docker:

```bash
# one-time: unpack the image's Nix closure and the Sky130 PDK
docker create --name lbl-export ghcr.io/librelane/librelane:3.0.17 /bin/true
docker export lbl-export -o E:\librelane-image.tar
wsl -d Ubuntu bash -lc 'sudo tar -xf /mnt/e/librelane-image.tar -C / nix'
# PDK (from the named volume) into a user-readable root
docker run --rm -v chiplab-librelane-ciel:/ciel -v "E:\:/out" \
  --entrypoint bash ghcr.io/librelane/librelane:3.0.17 \
  -lc "tar -czf /out/ciel-sky130.tar.gz -C /ciel ciel/sky130"
wsl -d Ubuntu bash -lc 'sudo mkdir -p /opt/ciel && sudo tar -xzf /mnt/e/ciel-sky130.tar.gz -C /opt/ciel --strip-components=1 && sudo chown -R $(id -u):$(id -g) /opt/ciel'
```

Then run from a copy of `rtl/` + `openlane/` on the WSL filesystem (the 9P mount is
slow and its `openlane/runs` may be root-owned):

```bash
BIN=/nix/store/1pkfh3p98m8i3jp642n3bznpjfq65i6m-python3-3.13.9-env/bin/librelane
mkdir -p ~/chiplab-native && cp -r /mnt/e/chips/main/rtl ~/chiplab-native/
cp /mnt/e/chips/main/openlane/<config>.json ~/chiplab-native/openlane/
cd ~/chiplab-native
# run it in a terminal that stays open until the flow ends (not detached)
$BIN --pdk-root /opt/ciel --run-tag <tag> \
  --skip OpenROAD.ResizerTimingPostCTS --skip OpenROAD.ResizerTimingPostGRT \
  openlane/<config>.json | tee ~/chiplab-native/full.log
```

Parity is verified: the native STA run of `sky130_wrap32_fitted.json` reproduced the
container numbers exactly (setup WNS **+0.3537 ns**, **19,660** max-slew violations).
The native path is also complete: `sky130_metrics.json` finished the whole flow with
**Magic DRC 0, KLayout DRC 0, LVS 0** and setup/hold WNS **+0.123 / +0.107 ns**.
Do **not** run `wsl --shutdown` while a flow is active. Copy the finished `final/metrics.json` (or the summary JSON) back into
`reports/`.

**Keep a WSL client attached.** Docker Desktop's distro and Ubuntu share one WSL2
utility VM, so Docker Desktop's periodic VM restarts also kill native Ubuntu
processes. With Docker Desktop stopped, WSL instead terminates the distro shortly
after the last `wsl.exe` client disconnects (observed 2026-11-10: a `setsid nohup`
flow died ≈16 s after its launching `wsl` call returned; boot history showed 1–3 min
sessions). Run long flows from a **persistent shell** (e.g. a background terminal that
stays open until the flow ends) instead of detaching them, or keep Docker Desktop
running and accept its restarts. Verify with `uptime`/`journalctl --list-boots` before
trusting a long run.

**This host is shared.** On 2026-11-10 the same Ubuntu distro was simultaneously used
by another session building `hscl-*` packages (`/home/tim/hscl1-src`, sudo installs at
22:31/22:38), and the VM restarted at 22:13, 22:20, 22:29 and 23:19, killing every
running flow. Check `journalctl -b -1 | grep -i hscl` and the boot list before a
multi-hour run; on a busy host, prefer bounded runs and `--last-run`/`--from` resumes.

On 2026-11-11 between 02:24 and 03:09 the distro was **cleanly shut down** every 3–5
minutes (journal shows `Reached target shutdown.target`, not a crash), which no client
attachment can prevent. If `journalctl --list-boots` shows such a cadence, physical
flows cannot finish; wait for the other workload to stop.

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
- When global routing is congested, the flow retries the whole `global_route` pass and
  disables NDR on one clock net per retry (`GRT-0273`), which costs ≈11 min per pass on
  this block. `CTS_APPLY_NDR` takes an enum — `"none" | "root_only" | "half" | "full"`,
  **not** a boolean (`False` is rejected as invalid) — and `"none"` skips that retry
  cycle when the clock rule is not needed for the experiment.

## 4. Resuming a killed run

LibreLane can continue an existing run tag, but the CLI still requires a config:

```powershell
... librelane --last-run openlane/<same-config>.json `
  --skip OpenROAD.ResizerTimingPostCTS --skip OpenROAD.ResizerTimingPostGRT
```

`--last-run` picks the newest run directory under `openlane/runs`. Repeat the same
`--skip` flags: skipped steps are not recorded as completed, so omitting them re-runs
those steps.

**Fast resume:** if only the tail of the flow is missing (e.g. the run died before
Magic DRC), use `--from` to start at a later step and reuse the saved state:

```powershell
... librelane --last-run openlane/<config>.json --from Magic.DRC
```

Verified 2026-11-11 on `sky130_wrap32_area_sized.json`: `--from Magic.DRC` jumped
straight to the Magic DRC step instead of replaying synthesis/placement/routing.

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
