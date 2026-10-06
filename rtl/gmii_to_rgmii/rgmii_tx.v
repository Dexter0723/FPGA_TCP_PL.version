`timescale 1ns / 1ps

// GMII to RGMII transmitter.  TX_ER is not present in this project, so both
// edges of TX_CTL carry TX_EN.
module rgmii_tx (
    input  wire       gmii_tx_clk,
    input  wire       gmii_tx_en,
    input  wire [7:0] gmii_txd,
    output wire       rgmii_txc,
    output wire       rgmii_tx_ctl,
    output wire [3:0] rgmii_txd
);

// Forward the transmit clock through an output DDR register, keeping clock,
// control, and data on equivalent I/O paths.
ODDR #(
    .DDR_CLK_EDGE("SAME_EDGE"),
    .INIT(1'b0),
    .SRTYPE("SYNC")
) u_forward_clock (
    .Q(rgmii_txc),
    .C(gmii_tx_clk),
    .CE(1'b1),
    .D1(1'b1),
    .D2(1'b0),
    .R(1'b0),
    .S(1'b0)
);

ODDR #(
    .DDR_CLK_EDGE("SAME_EDGE"),
    .INIT(1'b0),
    .SRTYPE("SYNC")
) u_control_output (
    .Q(rgmii_tx_ctl),
    .C(gmii_tx_clk),
    .CE(1'b1),
    .D1(gmii_tx_en),
    .D2(gmii_tx_en),
    .R(1'b0),
    .S(1'b0)
);

genvar bit_number;
generate
    for (bit_number = 0; bit_number < 4; bit_number = bit_number + 1) begin : g_tx_bits
        ODDR #(
            .DDR_CLK_EDGE("SAME_EDGE"),
            .INIT(1'b0),
            .SRTYPE("SYNC")
        ) u_data_output (
            .Q(rgmii_txd[bit_number]),
            .C(gmii_tx_clk),
            .CE(1'b1),
            .D1(gmii_txd[bit_number]),
            .D2(gmii_txd[bit_number + 4]),
            .R(1'b0),
            .S(1'b0)
        );
    end
endgenerate

endmodule

