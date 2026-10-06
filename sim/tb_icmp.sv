`timescale 1ns / 1ps

module tb_icmp;

localparam [47:0] LOCAL_MAC = 48'h00_11_22_33_44_55;
localparam [31:0] LOCAL_IP  = {8'd192, 8'd168, 8'd1, 8'd10};
localparam [47:0] PEER_MAC  = 48'h02_AA_BB_CC_DD_EE;
localparam [31:0] PEER_IP   = {8'd192, 8'd168, 8'd1, 8'd20};

reg clk = 1'b0;
reg rst_n = 1'b0;
reg gmii_rx_dv = 1'b0;
reg [7:0] gmii_rxd = 8'd0;
reg tx_start_en = 1'b0;

wire gmii_tx_en;
wire [7:0] gmii_txd;
wire rec_pkt_done;
wire tx_done;

reg packet_seen = 1'b0;
reg [7:0] captured [0:71];
integer captured_count = 0;
integer index;
reg [31:0] checksum_sum;
reg [31:0] expected_crc;

always #4 clk = ~clk;

icmp #(
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
    .rec_pkt_done(rec_pkt_done),
    .tx_start_en(tx_start_en),
    .tx_done(tx_done),
    .des_mac(PEER_MAC),
    .des_ip(PEER_IP)
);

always @(posedge clk) begin
    if (rec_pkt_done)
        packet_seen <= 1'b1;
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

task send_echo_request;
    integer n;
    begin
        for (n = 0; n < 7; n = n + 1) send_octet(8'h55);
        send_octet(8'hD5);

        send_octet(LOCAL_MAC[47:40]); send_octet(LOCAL_MAC[39:32]);
        send_octet(LOCAL_MAC[31:24]); send_octet(LOCAL_MAC[23:16]);
        send_octet(LOCAL_MAC[15:8]);  send_octet(LOCAL_MAC[7:0]);
        send_octet(PEER_MAC[47:40]);  send_octet(PEER_MAC[39:32]);
        send_octet(PEER_MAC[31:24]);  send_octet(PEER_MAC[23:16]);
        send_octet(PEER_MAC[15:8]);   send_octet(PEER_MAC[7:0]);
        send_octet(8'h08); send_octet(8'h00);

        send_octet(8'h45); send_octet(8'h00);
        send_octet(8'h00); send_octet(8'h21);
        send_octet(8'h12); send_octet(8'h34);
        send_octet(8'h40); send_octet(8'h00);
        send_octet(8'h40); send_octet(8'h01);
        send_octet(8'h00); send_octet(8'h00);
        send_octet(PEER_IP[31:24]); send_octet(PEER_IP[23:16]);
        send_octet(PEER_IP[15:8]);  send_octet(PEER_IP[7:0]);
        send_octet(LOCAL_IP[31:24]); send_octet(LOCAL_IP[23:16]);
        send_octet(LOCAL_IP[15:8]);  send_octet(LOCAL_IP[7:0]);

        send_octet(8'h08); send_octet(8'h00);
        send_octet(8'h00); send_octet(8'h00);
        send_octet(8'hBE); send_octet(8'hEF);
        send_octet(8'h00); send_octet(8'h07);
        send_octet(8'h01); send_octet(8'h02); send_octet(8'h03);
        send_octet(8'h04); send_octet(8'h05);

        for (n = 0; n < 17; n = n + 1) send_octet(8'h00);
        @(negedge clk);
        gmii_rx_dv = 1'b0;
        gmii_rxd   = 8'd0;
    end
endtask

initial begin
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    send_echo_request();
    repeat (3) @(posedge clk);
    if (!packet_seen)
        $fatal(1, "ICMP echo request was not accepted");

    @(negedge clk);
    tx_start_en = 1'b1;
    @(negedge clk);
    tx_start_en = 1'b0;

    wait (tx_done);
    @(negedge clk);

    if (captured_count != 72)
        $fatal(1, "ICMP reply length is %0d, expected 72", captured_count);
    if ({captured[8],captured[9],captured[10],captured[11],captured[12],captured[13]} !== PEER_MAC)
        $fatal(1, "Bad reply destination MAC");
    if ({captured[14],captured[15],captured[16],captured[17],captured[18],captured[19]} !== LOCAL_MAC)
        $fatal(1, "Bad reply source MAC");
    if ({captured[24],captured[25]} !== 16'd33)
        $fatal(1, "Bad IPv4 total length");
    if ({captured[38],captured[39],captured[40],captured[41]} !== PEER_IP)
        $fatal(1, "Bad reply destination IP");
    if (captured[42] !== 8'h00 || captured[43] !== 8'h00)
        $fatal(1, "Reply is not ICMP Echo Reply");
    if ({captured[46],captured[47],captured[48],captured[49]} !== 32'hBEEF_0007)
        $fatal(1, "Identifier or sequence mismatch");
    if ({captured[50],captured[51],captured[52],captured[53],captured[54]} !== 40'h01_02_03_04_05)
        $fatal(1, "Echo payload mismatch");

    checksum_sum = 32'd0;
    for (index = 22; index < 42; index = index + 2)
        checksum_sum = checksum_sum + {captured[index], captured[index+1]};
    checksum_sum = checksum_sum[31:16] + checksum_sum[15:0];
    checksum_sum = checksum_sum[31:16] + checksum_sum[15:0];
    if (checksum_sum[15:0] !== 16'hFFFF)
        $fatal(1, "Bad IPv4 header checksum");

    checksum_sum = 32'd0;
    for (index = 42; index < 54; index = index + 2)
        checksum_sum = checksum_sum + {captured[index], captured[index+1]};
    checksum_sum = checksum_sum + {captured[54], 8'h00};
    checksum_sum = checksum_sum[31:16] + checksum_sum[15:0];
    checksum_sum = checksum_sum[31:16] + checksum_sum[15:0];
    if (checksum_sum[15:0] !== 16'hFFFF)
        $fatal(1, "Bad ICMP checksum");

    expected_crc = 32'hFFFF_FFFF;
    for (index = 8; index < 68; index = index + 1)
        expected_crc = crc_byte(expected_crc, captured[index]);
    expected_crc = ~expected_crc;
    if ({captured[71],captured[70],captured[69],captured[68]} !== expected_crc)
        $fatal(1, "Bad ICMP reply FCS");

    $display("PASS: ICMP echo parsing, reply, checksums, payload, and FCS");
    $finish;
end

initial begin
    repeat (3000) @(posedge clk);
    $fatal(1, "ICMP simulation timeout");
end

endmodule
