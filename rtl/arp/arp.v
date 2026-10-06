`timescale 1ns / 1ps

module arp #(
    parameter [47:0] BOARD_MAC = 48'h00_11_22_33_44_55,
    parameter [31:0] BOARD_IP  = {8'd192, 8'd168, 8'd1, 8'd10},
    parameter [47:0] DES_MAC   = 48'hFF_FF_FF_FF_FF_FF,
    parameter [31:0] DES_IP    = {8'd192, 8'd168, 8'd1, 8'd102}
)(
    input  wire        rst_n,
    input  wire        gmii_rx_clk,
    input  wire        gmii_rx_dv,
    input  wire [7:0]  gmii_rxd,
    input  wire        gmii_tx_clk,
    output wire        gmii_tx_en,
    output wire [7:0]  gmii_txd,
    output wire        arp_rx_done,
    output wire        arp_rx_type,
    output wire [47:0] src_mac,
    output wire [31:0] src_ip,
    input  wire        arp_tx_en,
    input  wire        arp_tx_type,
    input  wire [47:0] des_mac,
    input  wire [31:0] des_ip,
    output wire        tx_done
);

wire        crc_en;
wire        crc_clr;
wire [31:0] crc_data;
wire [31:0] crc_next;

arp_rx #(
    .BOARD_MAC(BOARD_MAC),
    .BOARD_IP (BOARD_IP)
) u_arp_rx (
    .clk         (gmii_rx_clk),
    .rst_n       (rst_n),
    .gmii_rx_dv  (gmii_rx_dv),
    .gmii_rxd    (gmii_rxd),
    .arp_rx_done (arp_rx_done),
    .arp_rx_type (arp_rx_type),
    .src_mac     (src_mac),
    .src_ip      (src_ip)
);

arp_tx #(
    .BOARD_MAC(BOARD_MAC),
    .BOARD_IP (BOARD_IP),
    .DES_MAC  (DES_MAC),
    .DES_IP   (DES_IP)
) u_arp_tx (
    .clk         (gmii_tx_clk),
    .rst_n       (rst_n),
    .arp_tx_en   (arp_tx_en),
    .arp_tx_type (arp_tx_type),
    .des_mac     (des_mac),
    .des_ip      (des_ip),
    .crc_data    (crc_data),
    .crc_next    (crc_next[7:0]),
    .tx_done     (tx_done),
    .gmii_tx_en  (gmii_tx_en),
    .gmii_txd    (gmii_txd),
    .crc_en      (crc_en),
    .crc_clr     (crc_clr)
);

crc32_d8 u_crc32 (
    .clk      (gmii_tx_clk),
    .rst_n    (rst_n),
    .data     (gmii_txd),
    .crc_en   (crc_en),
    .crc_clr  (crc_clr),
    .crc_data (crc_data),
    .crc_next (crc_next)
);

endmodule

