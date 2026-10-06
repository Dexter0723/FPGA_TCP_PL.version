`timescale 1ns / 1ps

module icmp #(
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
    output wire        rec_pkt_done,
    input  wire        tx_start_en,
    output wire        tx_done,
    input  wire [47:0] des_mac,
    input  wire [31:0] des_ip
);

wire        payload_write;
wire [7:0]  payload_write_data;
wire [15:0] payload_length;
wire        payload_read;
wire [7:0]  payload_read_data;
wire [15:0] echo_id;
wire [15:0] echo_sequence;
wire [31:0] payload_checksum_sum;
wire        crc_en;
wire        crc_clr;
wire [31:0] crc_data;
wire [31:0] crc_next;

icmp_rx #(
    .BOARD_MAC(BOARD_MAC),
    .BOARD_IP (BOARD_IP)
) u_icmp_rx (
    .clk            (gmii_rx_clk),
    .rst_n          (rst_n),
    .gmii_rx_dv     (gmii_rx_dv),
    .gmii_rxd       (gmii_rxd),
    .rec_pkt_done   (rec_pkt_done),
    .rec_en         (payload_write),
    .rec_data       (payload_write_data),
    .rec_byte_num   (payload_length),
    .icmp_id        (echo_id),
    .icmp_seq       (echo_sequence),
    .reply_checksum (payload_checksum_sum)
);

icmp_payload_buffer u_payload_buffer (
    .clk     (gmii_rx_clk),
    .rst_n   (rst_n),
    .wr_en   (payload_write),
    .wr_data (payload_write_data),
    .rd_en   (payload_read),
    .rd_data (payload_read_data)
);

icmp_tx #(
    .BOARD_MAC(BOARD_MAC),
    .BOARD_IP (BOARD_IP),
    .DES_MAC  (DES_MAC),
    .DES_IP   (DES_IP)
) u_icmp_tx (
    .clk            (gmii_tx_clk),
    .rst_n          (rst_n),
    .reply_checksum (payload_checksum_sum),
    .icmp_id        (echo_id),
    .icmp_seq       (echo_sequence),
    .tx_start_en    (tx_start_en),
    .tx_data        (payload_read_data),
    .tx_byte_num    (payload_length),
    .des_mac        (des_mac),
    .des_ip         (des_ip),
    .crc_data       (crc_data),
    .crc_next       (crc_next[7:0]),
    .tx_done        (tx_done),
    .tx_req         (payload_read),
    .gmii_tx_en     (gmii_tx_en),
    .gmii_txd       (gmii_txd),
    .crc_en         (crc_en),
    .crc_clr        (crc_clr)
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

