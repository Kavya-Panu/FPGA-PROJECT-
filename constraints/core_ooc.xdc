# Illustrative core boundary budget. Replace with actual MAC/config/consumer
# constraints for the board integration. All ports here share the RX clock.
create_clock -name rx_clk -period 6.400 [get_ports clk]
set_clock_uncertainty 0.100 [get_clocks rx_clk]
set core_inputs [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_input_delay -clock rx_clk -max 1.000 $core_inputs
set_input_delay -clock rx_clk -min 0.000 $core_inputs
set_output_delay -clock rx_clk -max 1.000 [all_outputs]
set_output_delay -clock rx_clk -min 0.000 [all_outputs]
