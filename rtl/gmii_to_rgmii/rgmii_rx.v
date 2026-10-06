`timescale 1ns / 1ps

// RGMII receive adapter for Xilinx 7-series devices.  The PHY presents the
// low data nibble on the rising edge and the high nibble on the falling edge.
module rgmii_rx (
    input  wire       rgmii_rxc,
    input  wire       rgmii_rx_ctl,
    input  wire [3:0] rgmii_rxd,
    output wire       gmii_rx_clk,
    output wire       gmii_rx_dv,
    output wire [7:0] gmii_rxd
);

wire rx_clock_io;
wire rx_clock_global;
wire receive_valid;
wire receive_valid_xor_error;

BUFIO u_rx_io_clock (
    .I(rgmii_rxc),
    .O(rx_clock_io)
);

BUFG u_rx_global_clock (
    .I(rgmii_rxc),
    .O(rx_clock_global)
);

assign gmii_rx_clk = rx_clock_global;
assign gmii_rx_dv  = receive_valid;

IDDR #(
    .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),
    .INIT_Q1(1'b0),
    .INIT_Q2(1'b0),
    .SRTYPE("SYNC")
) u_control_input (
    .Q1(receive_valid),
    .Q2(receive_valid_xor_error),
    .C(rx_clock_io),
    .CE(1'b1),
    .D(rgmii_rx_ctl),
    .R(1'b0),
    .S(1'b0)
);

genvar bit_number;
generate
    for (bit_number = 0; bit_number < 4; bit_number = bit_number + 1) begin : g_rx_bits
        IDDR #(
            .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),
            .INIT_Q1(1'b0),
            .INIT_Q2(1'b0),
            .SRTYPE("SYNC")
        ) u_data_input (
            .Q1(gmii_rxd[bit_number]),
            .Q2(gmii_rxd[bit_number + 4]),
            .C(rx_clock_io),
            .CE(1'b1),
            .D(rgmii_rxd[bit_number]),
            .R(1'b0),
            .S(1'b0)
        );
    end
endgenerate

// RX_CTL on the falling edge carries RX_DV XOR RX_ER.  The current GMII
// interface has no RX_ER output, so only the rising-edge RX_DV is exported.
wire unused_receive_error = receive_valid ^ receive_valid_xor_error;

endmodule

