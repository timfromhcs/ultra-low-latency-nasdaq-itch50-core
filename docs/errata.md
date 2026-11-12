# Errata and known limitations

Applies to v0.3.1 (parser, book, Mold front-end, arbiter, metrics).
Nothing here is a fabrication claim; the RTL is simulation-verified only.

---

## E1 — No physical implementation or timing sign-off

**Status:** open, by design
**Impact:** Fmax, area and power are estimates. The 322.26 MHz figure comes from the
model in `docs/timing_cutthrough.*`, not from OpenSTA or a placed-and-routed design.
A LibreLane 3.0.17 sky130 pre-PnR run measures **WNS −9.14 ns at 3.10 ns** (≈81 MHz
Fmax estimate); the full flow is blocked by pin-count congestion (~1,100 top-level
pins on a 700 µm die), so no post-route STA, DRC or LVS result exists **for the
parser**. The small `itch_metrics` block did complete the full flow (0 DRC, 0 LVS,
timing closed at 10 ns) — that validates the flow, not the parser.
**Workaround:** treat timing as a target. Run LibreLane/OpenSTA in your own flow; the
`openlane/` configuration and `scripts/synth_*.sh` are starting points, not results.

## E2 — No 100G MAC, PCIe/DMA or host snapshot interface

**Status:** open
**Impact:** the core consumes AXI4-Stream beats. You must supply the network path
(MAC + framing) and the host path (DMA/PCIe or a register-mapped window). There is no
built-in snapshot command; the book outputs one event per message, and the host is
expected to accumulate the latest values.
**Workaround:** integrate behind your own MAC/DMA wrapper. The AXI4-Stream boundary
and the `bbo_*` event stream are the contract.

## E3 — Book is a bounded model, not a full-depth L3 book

**Status:** open, documented behavior
**Impact:** 16 locates, 16 price levels per side, 256 live orders (4-way associative).
Beyond that, updates are counted in `drops_overflow` / `level_overflow` and the
affected order is not tracked. Locates are indexed by their low 4 bits, so locate 16
aliases onto locate 0 (and so on); use locates 0–15.
**Workaround:** raise `LOCATES`/`LEVELS`/`ORDERS` parameters (area grows
superlinearly for the level tables) or run multiple instances partitioned by locate.

## E4 — `metrics_gap_count` is tied low inside `itch_top_book`

**Status:** open, intentional
**Impact:** gaps are a link-layer property. In the parser+book wrapper there is no
sequence tracking, so the gap counter stays 0; corrupt messages increment the drop
counter.
**Workaround:** instantiate `rtl/itch_metrics.sv` next to the Mold/arbiter stage and
drive `gap_pulse` from `mold_feed_arbiter.gap`.

## E5 — Retransmit request interface is a contract, not a protocol

**Status:** open, by design
**Impact:** the arbiter drives `req_valid`/`req_seq`/`req_count` and waits 256 clocks.
It does not emit MoldUDP64 retransmit requests itself and has no network stack.
**Workaround:** bridge the request signals to your Mold client. The multi-gap test
models the replay source; the timeout path is exercised ([1,2,3,6] with one abandon).

## E6 — Reset clears on the clock; ingress must wait for `ready`

**Status:** known behavior
**Impact:** `itch_top_book.ready` is low for ~800 clocks while tables clear, and the
parser is held in reset during that window. Traffic sent earlier is parsed but not
booked, and its messages are not replayed.
**Workaround:** gate the upstream `tvalid` on `ready`, or drain and retransmit after
reset.

## E7 — `m_axis_order_valid` pulses for corrupt messages

**Status:** known behavior
**Impact:** a corrupt/truncated message still produces a valid pulse with
`m_error_corrupt = 1` and a best-effort payload. Consumers that index tables must
filter it.
**Workaround:** use `m_axis_order_valid && !m_error_corrupt` as the event strobe, as
`itch_top_book` does.

## E8 — Counters are 32-bit and wrap

**Status:** known behavior
**Impact:** at 322 MHz the cycle counter wraps every ~13.3 s. Software must sample
often enough to unwrap, or use the deltas between samples.
**Workaround:** poll at a fixed interval and unwrap in software; the histogram and
message counters have the same width.

## E9 — ASIC/FPGA claims are not backed by a bitstream or a committed GDS

**Status:** partially resolved (wrapper only)
**Impact:** `docs/layout_preview.*` is an illustrative render, not a tapeout artifact.
Since 2026-11-12 the **wrapper** (`itch_wishbone_wrap`) has a completed Sky130 flow at
25 ns: 0 Magic/KLayout DRC, 0 LVS, setup +1.3333 ns, hold +0.0840 ns, Fmax ≈ 42.25 MHz
(`reports/openlane_25fx-full.json`). The GDS lives in the git-ignored run directory, not
in the repository, and the **parser-level/BBO blocks** have no sign-off. There is still
no bitstream and no fabricated silicon.
**Workaround:** label downstream use accordingly. The repository claims "tapeout-ready
RTL, not fabricated"; the wrapper P&R is evidence, not a tapeout.

## E10 — npm/PyPI registry publishing is pending

**Status:** open (external configuration)
**Impact:** release artifacts (tarball, wheel, sdist) are built and attached to GitHub
Releases, but registry publishing needs trusted-publisher/OIDC setup on the registry
side. `release.yml` contains opt-in publish steps gated on the repository variables
`NPM_PUBLISH` / `PYPI_PUBLISH`; they have not been run. Installing from the release
assets works today.
**Workaround:** `npm install ./chiplab-core-0.3.1.tgz` and
`pip install ./chiplab_itch-0.3.1-py3-none-any.whl`.

---

## E11 — CVC5 cover proof not re-verified with cvc5 1.3.2

**Status:** open (tool-version dependent)
**Impact:** `reports/formal.json` records CVC5 PASS for BMC, k-induction and covers from
the 2026-11-03 oss-cad-suite run. A 2026-11-10 local re-run with Ubuntu **cvc5 1.3.2**
passes BMC (depth 8, 47 s) and k-induction (2 s), but the cover checks (which need depth
20) did not finish within 14 minutes and were killed. The full depth-20 CVC5 run also
exceeded 30 minutes.
**Workaround:** Z3 is the gate and passes BMC + k-induction + covers in ≈90 s. Use the
pinned oss-cad-suite bundle in CI for the opt-in solver matrix.

---

## E12 — Physical limits of the wrapper and the missing level-table sign-off

**Status:** open (advisory findings + host limit)
**Impact:** the 25 ns wrapper sign-off is DRC/LVS/timing clean, but post-route STA still
reports **max-cap 2,529–3,320** and **max-slew up to 15,084–19,788** violations in the
advisory checkers (they do not fail the flow). Neither `RUN_POST_GRT_DESIGN_REPAIR` nor a
`MAX_FANOUT_CONSTRAINT: 8` retry reduces them (the latter makes slew worse), so they come
from the design/library limits at the ss corner. The level table
(`itch_top_of_book`, 32/4/4) has only a **pre-PnR** number (WNS −1.9742 ns, ≈37.1 MHz at
25 ns): its full flow needs ~9 GiB RSS (12 GB WSL) and 20+ min of routing plus 40+ min of
DRC, while this host restarts the WSL VM every ≈15 min under sustained load.
**Workaround:** treat the 25 ns wrapper as the signed-off evidence, use the level-table
pre-PnR number only as an estimate, and rerun the level-table flow on a stable host with
`openlane/sky130_leveltable.json`.

---

## Reporting

Open an issue with the RTL revision, the exact simulation command, and the observed
versus expected signal trace. Regression commands: `make lint`, `make cocotb`,
`make verify-deep`.
