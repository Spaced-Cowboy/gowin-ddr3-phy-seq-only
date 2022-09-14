//Copyright (C)2014-2022 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//GOWIN Version: 1.9.8.07 
//Created Time: 2022-09-13 16:24:08

#**************************************************************
# Input clock from the board
#**************************************************************
create_clock -name clk -period 37.037 -waveform {0 18.518} [get_ports {clk}]

#**************************************************************
# Create Generated Clocks
#**************************************************************
create_generated_clock -name clk_ddr3 -source [get_ports {clk}] -master_clock clk -divide_by 2 -multiply_by 22 -duty_cycle 50 [get_pins {BHG_DDR3_PLL/gowin_ddr_clocks/ddr3_pll1/CLKOUT}]
create_generated_clock -name clk_ddr3_rd -source [get_ports {clk}] -master_clock clk -divide_by 2 -multiply_by 22 -duty_cycle 50 [get_pins {BHG_DDR3_PLL/gowin_ddr_clocks/ddr3_pll1/CLKOUTP}]
create_generated_clock -name clk_ddr3_50 -source [get_ports {clk}] -master_clock clk -divide_by 4 -multiply_by 22 -duty_cycle 50 [get_pins {BHG_DDR3_PLL/gowin_ddr_clocks/ddr3_pll1/CLKOUTD}]

create_generated_clock -name clk_ddr3_wr -source [get_ports {clk}] -master_clock clk -divide_by 2 -multiply_by 22 -duty_cycle 50 -phase 270 [get_pins {BHG_DDR3_PLL/gowin_ddr_clocks/ddr3_pll2/CLKOUTP}]
create_generated_clock -name clk_ddr3_25 -source [get_ports {clk}] -master_clock clk -divide_by 8 -multiply_by 22 -duty_cycle 50 [get_pins {BHG_DDR3_PLL/gowin_ddr_clocks/ddr3_pll2/CLKOUTD}]

#**************************************************************
# Set Input Delay
#**************************************************************

# tSU = 0.5
set_input_delay -clock clk_ddr3_rd -max -add_delay             0.500 [get_ports {ddr_dq*[*]}]
set_input_delay -clock clk_ddr3_rd -max -add_delay -clock_fall 0.500 [get_ports {ddr_dq*[*]}]

set_input_delay -clock clk_ddr3_50 -max 0.5  [get_ports {uart_rxd}]

# tH  = 2.0
set_input_delay -clock clk_ddr3_rd -min -add_delay             2.000 [get_ports {ddr_dq*[*]}]
set_input_delay -clock clk_ddr3_rd -min -add_delay -clock_fall 2.000 [get_ports {ddr_dq*[*]}]

set_input_delay -clock clk_ddr3_50 -min 2.000  [get_ports {uart_rxd}]


#**************************************************************
# Set Output Delay
#**************************************************************

# tCO = -7.5 (?)
set_output_delay -clock clk_ddr3 -max -add_delay             -7.5 [get_ports {ddr*}]
set_output_delay -clock clk_ddr3 -max -add_delay -clock_fall -7.5 [get_ports {ddr*}]

set_output_delay -clock clk_ddr3_50 -max -7.5 [get_ports {led[*]}]
set_output_delay -clock clk_ddr3_50 -max -7.5 [get_ports {uart_txd}]

# tCOm = -3.8 (?)
set_output_delay -clock clk_ddr3 -min -add_delay             -3.8 [get_ports {ddr*}]
set_output_delay -clock clk_ddr3 -min -add_delay -clock_fall -3.8 [get_ports {ddr*}]

set_output_delay -clock clk_ddr3_50 -min -3.8 [get_ports {led[*]}]
set_output_delay -clock clk_ddr3_50 -min -3.8 [get_ports {uart_txd}]


#**************************************************************
# Set False Path
#**************************************************************
set_false_path -from [get_clocks {clk_ddr3_rd}] -to  [get_clocks {clk_ddr3_wr}]
set_false_path -from [get_clocks {clk_ddr3_wr}] -to  [get_clocks {clk_ddr3_rd}]

set_false_path -from [get_clocks {clk}] -to  [get_clocks {clk_ddr3_50}]
set_false_path -from [get_clocks {clk_ddr3_50}] -to  [get_clocks {clk}]

set_false_path -from [get_clocks {clk}] -to  [get_clocks {clk_ddr3_25}]
set_false_path -from [get_clocks {clk_ddr3_25}] -to  [get_clocks {clk}]

#**************************************************************
# Report more timing errors (default is 25)
#**************************************************************
report_timing -setup -max_paths 100 -max_common_paths 1

report_timing -setup -from_clock [get_clocks {clk_ddr3_wr}]
