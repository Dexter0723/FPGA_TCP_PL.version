`timescale 1ns / 1ps

module tb_rgmii;

reg rgmii_rxc = 1'b0;
reg rgmii_rx_ctl = 1'b0;
reg [3:0] rgmii_rxd = 4'd0;
reg gmii_tx_en = 1'b0;
reg [7:0] gmii_txd = 8'd0;

wire gmii_rx_clk;
wire gmii_rx_dv;
wire [7:0] gmii_rxd;
wire gmii_tx_clk;
wire rgmii_txc;
wire rgmii_tx_ctl;
wire [3:0] rgmii_txd;

always #4 rgmii_rxc = ~rgmii_rxc;

gmii_to_rgmii u_dut (
    .gmii_rx_clk(gmii_rx_clk),
    .gmii_rx_dv(gmii_rx_dv),
    .gmii_rxd(gmii_rxd),
    .gmii_tx_clk(gmii_tx_clk),
    .gmii_tx_en(gmii_tx_en),
    .gmii_txd(gmii_txd),
    .rgmii_rxc(rgmii_rxc),
    .rgmii_rx_ctl(rgmii_rx_ctl),
    .rgmii_rxd(rgmii_rxd),
    .rgmii_txc(rgmii_txc),
    .rgmii_tx_ctl(rgmii_tx_ctl),
    .rgmii_txd(rgmii_txd)
);

initial begin
    // TX: low nibble on rising edge, high nibble on falling edge.
    @(negedge rgmii_rxc);
    gmii_tx_en = 1'b1;
    gmii_txd   = 8'hA5;
    @(posedge rgmii_rxc); #1;
    if (rgmii_txd !== 4'h5 || rgmii_tx_ctl !== 1'b1 || rgmii_txc !== 1'b1)
        $fatal(1, "RGMII transmit rising-edge values are wrong");
    @(negedge rgmii_rxc); #1;
    if (rgmii_txd !== 4'hA || rgmii_tx_ctl !== 1'b1 || rgmii_txc !== 1'b0)
        $fatal(1, "RGMII transmit falling-edge values are wrong");

    // RX: present one byte and wait for the SAME_EDGE_PIPELINED output.
    rgmii_rx_ctl = 1'b1;
    rgmii_rxd = 4'hB;
    @(posedge rgmii_rxc);
    #1 rgmii_rxd = 4'hC;
    @(negedge rgmii_rxc);
    #1 rgmii_rxd = 4'h0;
    @(posedge rgmii_rxc); #1;
    if (gmii_rxd !== 8'hCB || gmii_rx_dv !== 1'b1)
        $fatal(1, "RGMII receive byte mismatch: %02h", gmii_rxd);

    $display("PASS: RGMII DDR transmit and receive mapping");
    $finish;
end

initial begin
    repeat (100) @(posedge rgmii_rxc);
    $fatal(1, "RGMII simulation timeout");
end

endmodule
