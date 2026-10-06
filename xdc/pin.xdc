## ATK-DF7020P / XC7Z020CLG400-2

## 50 MHz board clock and active-low reset
set_property PACKAGE_PIN U18 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
set_property PACKAGE_PIN N16 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]
create_clock -name sys_clk -period 20.000 [get_ports sys_clk]

## RGMII receive interface
set_property PACKAGE_PIN K17 [get_ports eth_rxc]
set_property PACKAGE_PIN E17 [get_ports eth_rx_ctl]
set_property PACKAGE_PIN B19 [get_ports {eth_rxd[0]}]
set_property PACKAGE_PIN A20 [get_ports {eth_rxd[1]}]
set_property PACKAGE_PIN H17 [get_ports {eth_rxd[2]}]
set_property PACKAGE_PIN H16 [get_ports {eth_rxd[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_rxc eth_rx_ctl eth_rxd[*]}]
create_clock -name eth_rxc -period 8.000 [get_ports eth_rxc]

## RGMII transmit interface
set_property PACKAGE_PIN B20 [get_ports eth_txc]
set_property PACKAGE_PIN K18 [get_ports eth_tx_ctl]
set_property PACKAGE_PIN D18 [get_ports {eth_txd[0]}]
set_property PACKAGE_PIN C20 [get_ports {eth_txd[1]}]
set_property PACKAGE_PIN D19 [get_ports {eth_txd[2]}]
set_property PACKAGE_PIN D20 [get_ports {eth_txd[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_txc eth_tx_ctl eth_txd[*]}]

## PHY reset and Clause 22 management interface
set_property PACKAGE_PIN G15 [get_ports eth_rst_n]
set_property PACKAGE_PIN F20 [get_ports eth_mdc]
set_property PACKAGE_PIN F19 [get_ports eth_mdio]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_rst_n eth_mdc eth_mdio}]

