`timescale 1ns / 1ps

module tb_arp;

localparam [47:0] LOCAL_MAC = 48'h00_11_22_33_44_55;
localparam [31:0] LOCAL_IP  = {8'd192, 8'd168, 8'd1, 8'd10};
localparam [47:0] PEER_MAC  = 48'h02_AA_BB_CC_DD_EE;
localparam [31:0] PEER_IP   = {8'd192, 8'd168, 8'd1, 8'd20};

reg clk = 1'b0;
reg rst_n = 1'b0;
reg gmii_rx_dv = 1'b0;
reg [7:0] gmii_rxd = 8'd0;
reg arp_tx_en = 1'b0;
reg arp_tx_type = 1'b0;
reg [47:0] des_mac = 48'd0;
reg [31:0] des_ip = 32'd0;

wire gmii_tx_en;
wire [7:0] gmii_txd;
wire arp_rx_done;
wire arp_rx_type;
wire [47:0] src_mac;
wire [31:0] src_ip;
wire tx_done;

reg rx_seen = 1'b0;
reg [7:0] captured [0:71];
integer captured_count = 0;
integer index;
reg [31:0] expected_crc;

always #4 clk = ~clk;

arp #(
    .BOARD_MAC(LOCAL_MAC),
    .BOARD_IP (LOCAL_IP)
) u_dut (
    .rst_n(rst_n),
    .gmii_rx_clk(clk),
    .gmii_rx_dv(gmii_rx_dv),
    .gmii_rxd(gmii_rxd),
    .gmii_tx_clk(clk),
    .gmii_tx_en(gmii_tx_en),
    .gmii_txd(gmii_txd),
    .arp_rx_done(arp_rx_done),
    .arp_rx_type(arp_rx_type),
    .src_mac(src_mac),
    .src_ip(src_ip),
    .arp_tx_en(arp_tx_en),
    .arp_tx_type(arp_tx_type),
    .des_mac(des_mac),
    .des_ip(des_ip),
    .tx_done(tx_done)
);

always @(posedge clk) begin
    if (arp_rx_done)
        rx_seen <= 1'b1;
    if (gmii_tx_en) begin
        if (captured_count < 72)
            captured[captured_count] <= gmii_txd;
        captured_count <= captured_count + 1;
    end
end

function [31:0] crc_byte;
    input [31:0] current;
    input [7:0] octet;
    integer bit_number;
    reg [31:0] value;
    begin
        value = current;
        for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
            if (value[0] ^ octet[bit_number])
                value = (value >> 1) ^ 32'hEDB8_8320;
            else
                value = value >> 1;
        end
        crc_byte = value;
    end
endfunction

task send_octet;
    input [7:0] value;
    begin
        @(negedge clk);
        gmii_rx_dv = 1'b1;
        gmii_rxd   = value;
        @(posedge clk);
    end
endtask

task send_arp_request;
    integer n;
    begin
        for (n = 0; n < 7; n = n + 1) send_octet(8'h55);
        send_octet(8'hD5);
        for (n = 0; n < 6; n = n + 1) send_octet(8'hFF);
        send_octet(PEER_MAC[47:40]); send_octet(PEER_MAC[39:32]);
        send_octet(PEER_MAC[31:24]); send_octet(PEER_MAC[23:16]);
        send_octet(PEER_MAC[15:8]);  send_octet(PEER_MAC[7:0]);
        send_octet(8'h08); send_octet(8'h06);
        send_octet(8'h00); send_octet(8'h01);
        send_octet(8'h08); send_octet(8'h00);
        send_octet(8'h06); send_octet(8'h04);
        send_octet(8'h00); send_octet(8'h01);
        send_octet(PEER_MAC[47:40]); send_octet(PEER_MAC[39:32]);
        send_octet(PEER_MAC[31:24]); send_octet(PEER_MAC[23:16]);
        send_octet(PEER_MAC[15:8]);  send_octet(PEER_MAC[7:0]);
        send_octet(PEER_IP[31:24]);  send_octet(PEER_IP[23:16]);
        send_octet(PEER_IP[15:8]);   send_octet(PEER_IP[7:0]);
        for (n = 0; n < 6; n = n + 1) send_octet(8'h00);
        send_octet(LOCAL_IP[31:24]); send_octet(LOCAL_IP[23:16]);
        send_octet(LOCAL_IP[15:8]);  send_octet(LOCAL_IP[7:0]);
        repeat (4) send_octet(8'h00);
        @(negedge clk);
        gmii_rx_dv = 1'b0;
        gmii_rxd   = 8'd0;
    end
endtask

initial begin
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    send_arp_request();
    repeat (2) @(posedge clk);
    if (!rx_seen)
        $fatal(1, "ARP request was not accepted");
    if (arp_rx_type !== 1'b0 || src_mac !== PEER_MAC || src_ip !== PEER_IP)
        $fatal(1, "ARP receive fields are incorrect");

    @(negedge clk);
    des_mac      = PEER_MAC;
    des_ip       = PEER_IP;
    arp_tx_type  = 1'b1;
    arp_tx_en    = 1'b1;
    @(negedge clk);
    arp_tx_en    = 1'b0;

    wait (tx_done);
    @(negedge clk);

    if (captured_count != 72)
        $fatal(1, "ARP reply length is %0d, expected 72", captured_count);
    for (index = 0; index < 7; index = index + 1)
        if (captured[index] !== 8'h55)
            $fatal(1, "Bad preamble byte %0d", index);
    if (captured[7] !== 8'hD5)
        $fatal(1, "Bad SFD");
    if ({captured[8],captured[9],captured[10],captured[11],captured[12],captured[13]} !== PEER_MAC)
        $fatal(1, "Bad Ethernet destination MAC");
    if ({captured[28],captured[29]} !== 16'h0002)
        $fatal(1, "Bad ARP reply operation");

    expected_crc = 32'hFFFF_FFFF;
    for (index = 8; index < 68; index = index + 1)
        expected_crc = crc_byte(expected_crc, captured[index]);
    expected_crc = ~expected_crc;
    if ({captured[71],captured[70],captured[69],captured[68]} !== expected_crc)
        $fatal(1, "Bad ARP FCS");

    $display("PASS: ARP request parsing, reply generation, and FCS");
    $finish;
end

initial begin
    repeat (2000) @(posedge clk);
    $fatal(1, "ARP simulation timeout");
end

endmodule

