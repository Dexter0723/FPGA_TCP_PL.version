`timescale 1ns / 1ps

module tb_tcp_engine;

localparam [47:0] BOARD_MAC  = 48'h00_11_22_33_44_55;
localparam [31:0] BOARD_IP   = {8'd192, 8'd168, 8'd1, 8'd10};
localparam [15:0] BOARD_PORT = 16'd5000;
localparam [47:0] HOST_MAC   = 48'h02_00_00_00_00_01;
localparam [31:0] HOST_IP    = {8'd192, 8'd168, 8'd1, 8'd100};
localparam [15:0] HOST_PORT  = 16'd40000;
localparam [31:0] HOST_ISN   = 32'h0102_0304;
localparam [31:0] SERVER_ISN = 32'h1234_5678;

reg clk = 1'b0;
reg rst_n = 1'b0;
always #4 clk = ~clk;

reg        host_tx_start;
reg [31:0] host_seq;
reg [31:0] host_ack;
reg [7:0]  host_flags;
reg [15:0] host_ip_id;
wire       host_tx_busy;
wire       host_tx_done;
wire       host_gmii_tx_en;
wire [7:0] host_gmii_txd;
wire [15:0] host_payload_addr;

wire       board_tx_request;
wire       board_tx_grant = board_tx_request;
wire       board_gmii_tx_en;
wire [7:0] board_gmii_txd;
wire       board_tx_busy;
wire       board_tx_done;
wire       board_connected;

reg        app_valid;
reg [7:0]  app_data;
wire       app_ready;
wire [31:0] stat_bytes;
wire [31:0] stat_retries;

wire       host_rx_event;
wire       host_rx_checksum_ok;
wire [47:0] host_rx_remote_mac;
wire [31:0] host_rx_remote_ip;
wire [15:0] host_rx_remote_port;
wire [31:0] host_rx_seq;
wire [31:0] host_rx_ack;
wire [7:0]  host_rx_flags;
wire [15:0] host_rx_window;
wire [15:0] host_rx_payload_length;

integer data_frame_count;
reg [31:0] first_data_seq;
reg [31:0] second_data_seq;
reg        synack_seen;

tcp_tx #(
    .LOCAL_MAC      (HOST_MAC),
    .LOCAL_IP       (HOST_IP),
    .LOCAL_PORT     (HOST_PORT),
    .RAM_ADDR_WIDTH (16)
) u_host_tx (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .tx_start              (host_tx_start),
    .remote_mac            (BOARD_MAC),
    .remote_ip             (BOARD_IP),
    .remote_port           (BOARD_PORT),
    .sequence_number       (host_seq),
    .acknowledgment_number (host_ack),
    .tcp_flags             (host_flags),
    .local_window          (16'd60000),
    .payload_length        (16'd0),
    .payload_start         (16'd0),
    .payload_sum           (32'd0),
    .ip_identification     (host_ip_id),
    .payload_rd_addr       (host_payload_addr),
    .payload_rd_data       (8'd0),
    .busy                  (host_tx_busy),
    .tx_done               (host_tx_done),
    .gmii_tx_en            (host_gmii_tx_en),
    .gmii_txd              (host_gmii_txd)
);

tcp_engine #(
    .LOCAL_MAC        (BOARD_MAC),
    .LOCAL_IP         (BOARD_IP),
    .LOCAL_PORT       (BOARD_PORT),
    .INITIAL_SEQUENCE (SERVER_ISN),
    .RTO_CYCLES       (32'd200000)
) u_dut (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .gmii_rx_dv            (host_gmii_tx_en),
    .gmii_rxd              (host_gmii_txd),
    .app_tx_valid          (app_valid),
    .app_tx_data           (app_data),
    .app_tx_flush          (1'b0),
    .app_tx_ready          (app_ready),
    .tx_request            (board_tx_request),
    .tx_grant              (board_tx_grant),
    .gmii_tx_en            (board_gmii_tx_en),
    .gmii_txd              (board_gmii_txd),
    .tx_busy               (board_tx_busy),
    .tx_done               (board_tx_done),
    .connected             (board_connected),
    .stat_tx_payload_bytes (stat_bytes),
    .stat_retransmissions  (stat_retries)
);

tcp_rx #(
    .LOCAL_MAC  (HOST_MAC),
    .LOCAL_IP   (HOST_IP),
    .LOCAL_PORT (HOST_PORT)
) u_host_rx (
    .clk            (clk),
    .rst_n          (rst_n),
    .gmii_rx_dv     (board_gmii_tx_en),
    .gmii_rxd       (board_gmii_txd),
    .event_valid    (host_rx_event),
    .checksum_ok    (host_rx_checksum_ok),
    .remote_mac     (host_rx_remote_mac),
    .remote_ip      (host_rx_remote_ip),
    .remote_port    (host_rx_remote_port),
    .seq_num        (host_rx_seq),
    .ack_num        (host_rx_ack),
    .flags          (host_rx_flags),
    .window_size    (host_rx_window),
    .payload_length (host_rx_payload_length)
);

always @(posedge clk) begin
    if (!rst_n) begin
        app_valid <= 1'b0;
        app_data  <= 8'd0;
    end else begin
        app_valid <= board_connected;
        if (app_valid && app_ready)
            app_data <= app_data + 1'b1;
    end
end

always @(posedge clk) begin
    if (!rst_n) begin
        data_frame_count <= 0;
        first_data_seq   <= 32'd0;
        second_data_seq  <= 32'd0;
        synack_seen      <= 1'b0;
    end else if (host_rx_event) begin
        if (!host_rx_checksum_ok)
            $fatal(1, "Received frame has an invalid IPv4 or TCP checksum");
        if (host_rx_flags == 8'h12) begin
            if (host_rx_ack != (HOST_ISN + 1))
                $fatal(1, "SYN+ACK acknowledgment number is incorrect");
            if (host_rx_seq != SERVER_ISN)
                $fatal(1, "SYN+ACK sequence number is incorrect");
            synack_seen <= 1'b1;
        end else if ((host_rx_flags == 8'h18) &&
                     (host_rx_payload_length != 16'd0)) begin
            data_frame_count <= data_frame_count + 1;
            if (host_rx_payload_length != 16'd1460)
                $fatal(1, "Expected a full 1460-byte TCP segment");
            if (data_frame_count == 0)
                first_data_seq <= host_rx_seq;
            if (data_frame_count == 1) begin
                second_data_seq <= host_rx_seq;
                if (host_rx_seq != (first_data_seq + 32'd1460))
                    $fatal(1, "Sliding-window segment sequence is not contiguous");
            end
        end
    end
end

task automatic send_host_control;
    input [31:0] seq_value;
    input [31:0] ack_value;
    input [7:0]  flag_value;
    begin
        while (host_tx_busy)
            @(posedge clk);
        @(posedge clk);
        host_seq      <= seq_value;
        host_ack      <= ack_value;
        host_flags    <= flag_value;
        host_ip_id    <= host_ip_id + 1'b1;
        host_tx_start <= 1'b1;
        @(posedge clk);
        host_tx_start <= 1'b0;
        while (!host_tx_done)
            @(posedge clk);
    end
endtask

initial begin
    host_tx_start = 1'b0;
    host_seq      = 32'd0;
    host_ack      = 32'd0;
    host_flags    = 8'd0;
    host_ip_id    = 16'd1;

    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (10) @(posedge clk);

    send_host_control(HOST_ISN, 32'd0, 8'h02);
    wait (synack_seen);
    send_host_control(HOST_ISN + 1'b1, SERVER_ISN + 1'b1, 8'h10);

    wait (board_connected);
    wait (data_frame_count >= 2);

    // Cumulative ACK for two data segments proves that multiple segments
    // were in flight before the first data ACK was returned.
    send_host_control(HOST_ISN + 1'b1,
                      SERVER_ISN + 1'b1 + 32'd2920,
                      8'h10);

    repeat (200) @(posedge clk);
    if (stat_bytes < 32'd2920)
        $fatal(1, "Payload byte counter did not advance");
    if (stat_retries != 32'd0)
        $fatal(1, "Unexpected retransmission during clean-link test");

    $display("PASS: handshake, checksums, 1460-byte data, and sliding window verified");
    $finish;
end

initial begin
    repeat (30000) @(posedge clk);
    $fatal(1, "Simulation timeout");
end

endmodule

