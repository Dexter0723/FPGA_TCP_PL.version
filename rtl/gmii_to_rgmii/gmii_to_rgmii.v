`timescale 1ns / 1ps

module gmii_to_rgmii (
    output wire       gmii_rx_clk,
    output wire       gmii_rx_dv,
    output wire [7:0] gmii_rxd,
    output wire       gmii_tx_clk,
    input  wire       gmii_tx_en,
    input  wire [7:0] gmii_txd,
    input  wire       rgmii_rxc,
    input  wire       rgmii_rx_ctl,
    input  wire [3:0] rgmii_rxd,
    output wire       rgmii_txc,
    output wire       rgmii_tx_ctl,
    output wire [3:0] rgmii_txd
);

// The existing TOE core is clocked from the PHY's recovered receive clock.
// Preserve that clocking contract for drop-in compatibility.
assign gmii_tx_clk = gmii_rx_clk;

rgmii_rx u_receive (
    .rgmii_rxc    (rgmii_rxc),
    .rgmii_rx_ctl (rgmii_rx_ctl),
    .rgmii_rxd    (rgmii_rxd),
    .gmii_rx_clk  (gmii_rx_clk),
    .gmii_rx_dv   (gmii_rx_dv),
    .gmii_rxd     (gmii_rxd)
);

rgmii_tx u_transmit (
    .gmii_tx_clk  (gmii_tx_clk),
    .gmii_tx_en   (gmii_tx_en),
    .gmii_txd     (gmii_txd),
    .rgmii_txc    (rgmii_txc),
    .rgmii_tx_ctl (rgmii_tx_ctl),
    .rgmii_txd    (rgmii_txd)
);

endmodule

