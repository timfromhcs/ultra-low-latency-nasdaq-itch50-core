# ============================================================================
# SDC Timing Constraints for ultra_low_latency_nasdaq_itch50_cutthrough
# Target: 322.26 MHz Clock (Tclk = 3.10 ns)
# ============================================================================
create_clock -name clk -period 3.10 [get_ports clk]

# Clock Uncertainty & Jitter
set_clock_uncertainty 0.05 [get_clocks clk]
set_clock_transition 0.02 [get_clocks clk]

# Input / Output Delays
set_input_delay -clock clk -max 0.60 [get_ports s_axis_*]
set_input_delay -clock clk -min 0.10 [get_ports s_axis_*]
set_input_delay -clock clk -max 0.60 [get_ports rst_n]
set_input_delay -clock clk -min 0.10 [get_ports rst_n]

set_output_delay -clock clk -max 0.60 [get_ports m_*]
set_output_delay -clock clk -min 0.10 [get_ports m_*]

# Asynchronous / Combinatorial Bypass Constraints (Max delay <= 1.10 ns)
set_max_delay 1.10 -from [get_ports s_axis_tdata*] -to [get_ports raw_*]