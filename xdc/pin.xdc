#=====================================================================================
#General
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports sys_clk]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports sys_rst_n]
#=====================================================================================
#=====================================================================================
#Clock
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]
create_clock -period 8.000 -name eth_rxc [get_ports eth_rxc]

create_generated_clock \
    -name adc_clk \
    -source [get_ports sys_clk] \
    -divide_by 2 \
    [get_pins adc_inst/adc_clk_div_reg/Q]
#=====================================================================================
#=====================================================================================
#AD
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN U17} [get_ports {ad_data[7]}] 
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN T16} [get_ports {ad_data[6]}] 
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN Y16} [get_ports {ad_data[5]}] 
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN Y17} [get_ports {ad_data[4]}] 
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN T15} [get_ports {ad_data[3]}] 
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN T14} [get_ports {ad_data[2]}] 
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN W16} [get_ports {ad_data[1]}] 
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN V16} [get_ports {ad_data[0]}] 
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN V18} [get_ports adc_clk] 
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN V17} [get_ports ad_otr]
#=====================================================================================
#=====================================================================================
#Ethernet PHY
set_property -dict {PACKAGE_PIN G15 IOSTANDARD LVCMOS33} [get_ports eth_rst_n]
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports eth_rxc]
set_property -dict {PACKAGE_PIN E17 IOSTANDARD LVCMOS33} [get_ports eth_rx_ctl]
set_property -dict {PACKAGE_PIN B19 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[0]}]
set_property -dict {PACKAGE_PIN A20 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[1]}]
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[2]}]
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[3]}]

set_property -dict {PACKAGE_PIN B20 IOSTANDARD LVCMOS33} [get_ports eth_txc]
set_property -dict {PACKAGE_PIN K18 IOSTANDARD LVCMOS33} [get_ports eth_tx_ctl]
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS33} [get_ports {eth_txd[0]}]
set_property -dict {PACKAGE_PIN C20 IOSTANDARD LVCMOS33} [get_ports {eth_txd[1]}]
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} [get_ports {eth_txd[2]}]
set_property -dict {PACKAGE_PIN D20 IOSTANDARD LVCMOS33} [get_ports {eth_txd[3]}]

set_property -dict {PACKAGE_PIN F20 IOSTANDARD LVCMOS33} [get_ports eth_mdc]
set_property -dict {PACKAGE_PIN F19 IOSTANDARD LVCMOS33} [get_ports eth_mdio]
#=====================================================================================
