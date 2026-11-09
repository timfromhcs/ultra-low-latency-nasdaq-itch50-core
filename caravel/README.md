# Caravel integration

`user_project_wrapper.v` in this directory is a drop-in wrapper with Caravel's exact
module name and port list. It instantiates `itch_caravel_wrap` from `rtl/`.

## Port mapping

| Caravel | ChipLab |
|---|---|
| `io_in[31:0]` | ITCH byte stream data |
| `io_in[35:32]` | `tkeep` |
| `io_in[36]` | `tvalid` |
| `io_in[37]` | `tlast` |
| `io_out[0]` | `tready`; all other `io_out` are 0 |
| `io_oeb` | `38'h3F_FFFF_FFFE` (only bit 0 is an output) |
| `wbs_adr_i[6:2]` | host register word address (0–10) |
| `wbs_dat_o`, `wbs_ack_o` | register value, one-cycle ACK |
| `wb_clk_i` / `wb_rst_i` | clock / active-high reset |
| `la_data_in`, `la_oenb` | unused; `la_data_out = 0` |
| `user_irq` | `3'b000` |

The register map is in `../docs/register-map.md`.

## What is verified here

- Verilator lint with the `user_project_wrapper` top: clean.
- `tb/run_caravel_upw_cocotb.py` runs the Caravel-shaped test against that top: two
  messages over `io_in`, Wishbone reads of count/type/locate/shares/ref → PASS.

## What has **not** been run

The actual Caravel harness (pad ring, `caravel.v`, Caravel simulation and LibreLane
hardening) has not been executed. It needs the Caravel SoC repository and a PDK/sim
environment:

```bash
git clone https://github.com/efabless/caravel_user_project.git
cd caravel_user_project
make setup          # installs the PDK (volare) and the Caravel sim environment
```

Then copy `caravel/user_project_wrapper.v` and the `rtl/*.sv` files into
`verilog/rtl/`, add them to the project's Verilog file list, and run `make verify`.
Expect to adjust the include order (`itch_pkg.sv` first) and the pin/IO plan.

Do not claim a Caravel sign-off until that run exists.
