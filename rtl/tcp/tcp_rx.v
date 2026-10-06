`timescale 1ns / 1ps

// Single-flow IPv4/TCP receiver for the PL TCP offload engine.
// The GMII stream is expected to include Ethernet preamble/SFD and FCS.
// Ethernet FCS bytes are ignored; IPv4 and TCP checksums are verified.
module tcp_rx #(
           parameter [47:0] LOCAL_MAC   = 48'h00_11_22_33_44_55,
           parameter [31:0] LOCAL_IP    = {8'd192, 8'd168, 8'd1, 8'd10},
           parameter [15:0] LOCAL_PORT  = 16'd5000,
           parameter [15:0] MAX_PAYLOAD = 16'd1460
       )(
           input  wire        clk,
           input  wire        rst_n,
           input  wire        gmii_rx_dv,
           input  wire [7:0]  gmii_rxd,

           output reg         event_valid,
           output reg         checksum_ok,
           output reg  [47:0] remote_mac,
           output reg  [31:0] remote_ip,
           output reg  [15:0] remote_port,
           output reg  [31:0] seq_num,
           output reg  [31:0] ack_num,
           output reg  [7:0]  flags,
           output reg  [15:0] window_size,
           output reg  [15:0] payload_length,

           output reg         payload_wr_en,
           output reg  [10:0] payload_wr_addr,
           output reg  [7:0]  payload_wr_data
       );

reg         in_frame;
reg  [3:0]  preamble_count;
reg  [15:0] frame_index;

reg  [47:0] dst_mac_work;
reg  [47:0] src_mac_work;
reg  [15:0] eth_type_work;
reg  [31:0] src_ip_work;
reg  [31:0] dst_ip_work;
reg  [15:0] src_port_work;
reg  [15:0] dst_port_work;
reg  [31:0] seq_work;
reg  [31:0] ack_work;
reg  [7:0]  flags_work;
reg  [15:0] window_work;
reg  [7:0]  ip_header_bytes;
reg  [15:0] ip_total_length;
reg  [15:0] tcp_length;
reg  [7:0]  tcp_header_bytes;
reg  [15:0] fragment_field;

reg         mac_ok;
reg         eth_ok;
reg         ipv4_ok;
reg         protocol_ok;
reg         ip_dest_ok;
reg         fragment_ok;
reg         port_ok;
reg         tcp_started;
reg  [15:0] tcp_bytes_seen;

reg  [31:0] ip_sum;
reg  [31:0] ip_sum_complete;
reg  [7:0]  ip_high_byte;
reg         ip_pair_pending;

reg  [31:0] tcp_sum;
reg  [7:0]  tcp_high_byte;
reg         tcp_pair_pending;

reg         finalize_pending;
reg         candidate_latched;
reg  [31:0] tcp_sum_latched;

wire [15:0] tcp_start_index = 16'd14 + {8'd0, ip_header_bytes};

function [15:0] fold_sum16;
    input [31:0] value;
    reg [32:0] temp;
    begin
        temp = {1'b0, value[31:16]} + {1'b0, value[15:0]};
        temp = {16'd0, temp[16]} + {17'd0, temp[15:0]};
        temp = {16'd0, temp[16]} + {17'd0, temp[15:0]};
        fold_sum16 = temp[15:0];
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        in_frame          <= 1'b0;
        preamble_count     <= 4'd0;
        frame_index        <= 16'd0;
        dst_mac_work       <= 48'd0;
        src_mac_work       <= 48'd0;
        eth_type_work      <= 16'd0;
        src_ip_work        <= 32'd0;
        dst_ip_work        <= 32'd0;
        src_port_work      <= 16'd0;
        dst_port_work      <= 16'd0;
        seq_work           <= 32'd0;
        ack_work           <= 32'd0;
        flags_work         <= 8'd0;
        window_work        <= 16'd0;
        ip_header_bytes    <= 8'd0;
        ip_total_length    <= 16'd0;
        tcp_length         <= 16'd0;
        tcp_header_bytes   <= 8'd20;
        fragment_field     <= 16'd0;
        mac_ok             <= 1'b0;
        eth_ok             <= 1'b0;
        ipv4_ok            <= 1'b0;
        protocol_ok        <= 1'b0;
        ip_dest_ok         <= 1'b0;
        fragment_ok        <= 1'b0;
        port_ok            <= 1'b0;
        tcp_started        <= 1'b0;
        tcp_bytes_seen     <= 16'd0;
        ip_sum             <= 32'd0;
        ip_sum_complete    <= 32'd0;
        ip_high_byte       <= 8'd0;
        ip_pair_pending    <= 1'b0;
        tcp_sum            <= 32'd0;
        tcp_high_byte      <= 8'd0;
        tcp_pair_pending   <= 1'b0;
        finalize_pending   <= 1'b0;
        candidate_latched  <= 1'b0;
        tcp_sum_latched    <= 32'd0;
        event_valid        <= 1'b0;
        checksum_ok        <= 1'b0;
        remote_mac         <= 48'd0;
        remote_ip          <= 32'd0;
        remote_port        <= 16'd0;
        seq_num            <= 32'd0;
        ack_num            <= 32'd0;
        flags              <= 8'd0;
        window_size        <= 16'd0;
        payload_length     <= 16'd0;
        payload_wr_en      <= 1'b0;
        payload_wr_addr    <= 11'd0;
        payload_wr_data    <= 8'd0;
    end
    else begin
        event_valid        <= 1'b0;
        payload_wr_en      <= 1'b0;


        if (finalize_pending) begin
            finalize_pending <= 1'b0;
            event_valid      <= candidate_latched;
            checksum_ok      <= (fold_sum16(ip_sum_complete) == 16'hffff) &&
                             (fold_sum16(tcp_sum_latched) == 16'hffff);
            remote_mac       <= src_mac_work;
            remote_ip        <= src_ip_work;
            remote_port      <= src_port_work;
            seq_num          <= seq_work;
            ack_num          <= ack_work;
            flags            <= flags_work;
            window_size      <= window_work;
            if ((tcp_header_bytes >= 8'd20) &&
                    (tcp_length >= {8'd0, tcp_header_bytes}))
                payload_length <= tcp_length - {8'd0, tcp_header_bytes};
            else
                payload_length <= 16'd0;
        end

        if (gmii_rx_dv) begin
            if (!in_frame) begin
                if (gmii_rxd == 8'h55) begin
                    if (preamble_count != 4'hf)
                        preamble_count <= preamble_count + 1'b1;
                end
                else if ((gmii_rxd == 8'hd5) && (preamble_count >= 4'd7)) begin
                    in_frame         <= 1'b1;
                    preamble_count    <= 4'd0;
                    frame_index       <= 16'd0;
                    dst_mac_work      <= 48'd0;
                    src_mac_work      <= 48'd0;
                    eth_type_work     <= 16'd0;
                    src_ip_work       <= 32'd0;
                    dst_ip_work       <= 32'd0;
                    src_port_work     <= 16'd0;
                    dst_port_work     <= 16'd0;
                    seq_work          <= 32'd0;
                    ack_work          <= 32'd0;
                    flags_work        <= 8'd0;
                    window_work       <= 16'd0;
                    ip_header_bytes   <= 8'd0;
                    ip_total_length   <= 16'd0;
                    tcp_length        <= 16'd0;
                    tcp_header_bytes  <= 8'd20;
                    fragment_field    <= 16'd0;
                    mac_ok            <= 1'b0;
                    eth_ok            <= 1'b0;
                    ipv4_ok           <= 1'b0;
                    protocol_ok       <= 1'b0;
                    ip_dest_ok        <= 1'b0;
                    fragment_ok       <= 1'b0;
                    port_ok           <= 1'b0;
                    tcp_started       <= 1'b0;
                    tcp_bytes_seen    <= 16'd0;
                    ip_sum            <= 32'd0;
                    ip_sum_complete   <= 32'd0;
                    ip_pair_pending   <= 1'b0;
                    tcp_sum           <= 32'd0;
                    tcp_pair_pending  <= 1'b0;
                end
                else begin
                    preamble_count <= 4'd0;
                end
            end
            else begin
                frame_index <= frame_index + 1'b1;

                if (frame_index <= 16'd5)
                    dst_mac_work <= {dst_mac_work[39:0], gmii_rxd};
                if (frame_index == 16'd5)
                    mac_ok <= ({dst_mac_work[39:0], gmii_rxd} == LOCAL_MAC) ||
                           ({dst_mac_work[39:0], gmii_rxd} == 48'hff_ff_ff_ff_ff_ff);

                if ((frame_index >= 16'd6) && (frame_index <= 16'd11))
                    src_mac_work <= {src_mac_work[39:0], gmii_rxd};

                if (frame_index == 16'd12)
                    eth_type_work[15:8] <= gmii_rxd;
                if (frame_index == 16'd13) begin
                    eth_type_work[7:0] <= gmii_rxd;
                    eth_ok <= ({eth_type_work[15:8], gmii_rxd} == 16'h0800);
                end

                // IPv4 header checksum and fields.
                if (frame_index == 16'd14) begin
                    ip_header_bytes <= {gmii_rxd[3:0], 2'b00};
                    ipv4_ok         <= (gmii_rxd[7:4] == 4'd4) &&
                                    (gmii_rxd[3:0] >= 4'd5);
                    ip_high_byte    <= gmii_rxd;
                    ip_pair_pending <= 1'b1;
                    ip_sum          <= 32'd0;
                end
                else if ((frame_index > 16'd14) &&
                         (frame_index < (16'd14 + {8'd0, ip_header_bytes}))) begin
                    if (ip_pair_pending) begin
                        ip_sum          <= ip_sum + {16'd0, ip_high_byte, gmii_rxd};
                        ip_pair_pending <= 1'b0;
                        if (frame_index == (16'd13 + {8'd0, ip_header_bytes}))
                            ip_sum_complete <= ip_sum + {16'd0, ip_high_byte, gmii_rxd};
                    end
                    else begin
                        ip_high_byte    <= gmii_rxd;
                        ip_pair_pending <= 1'b1;
                    end
                end

                if (frame_index == 16'd16)
                    ip_total_length[15:8] <= gmii_rxd;
                if (frame_index == 16'd17) begin
                    ip_total_length[7:0] <= gmii_rxd;
                    // IHL was captured three bytes earlier, so the TCP length
                    // can be registered well before the TCP header arrives.
                    tcp_length <= {ip_total_length[15:8], gmii_rxd} -
                               {8'd0, ip_header_bytes};
                end
                if (frame_index == 16'd20)
                    fragment_field[15:8] <= gmii_rxd;
                if (frame_index == 16'd21) begin
                    fragment_field[7:0] <= gmii_rxd;
                    fragment_ok <= (({fragment_field[15:8], gmii_rxd} & 16'h3fff) == 16'd0);
                end
                if (frame_index == 16'd23)
                    protocol_ok <= (gmii_rxd == 8'd6);
                if ((frame_index >= 16'd26) && (frame_index <= 16'd29))
                    src_ip_work <= {src_ip_work[23:0], gmii_rxd};
                if ((frame_index >= 16'd30) && (frame_index <= 16'd33))
                    dst_ip_work <= {dst_ip_work[23:0], gmii_rxd};
                if (frame_index == 16'd33)
                    ip_dest_ok <= ({dst_ip_work[23:0], gmii_rxd} == LOCAL_IP);

                // Build the TCP pseudo-header sum while the source and
                // destination IPv4 address bytes pass through the parser.
                // This removes a six-operand adder from the first TCP byte.
                if (frame_index == 16'd27)
                    tcp_sum <= tcp_sum +
                            {16'd0, src_ip_work[7:0], gmii_rxd};
                if (frame_index == 16'd29)
                    tcp_sum <= tcp_sum +
                            {16'd0, src_ip_work[7:0], gmii_rxd};
                if (frame_index == 16'd31)
                    tcp_sum <= tcp_sum +
                            {16'd0, dst_ip_work[7:0], gmii_rxd};
                if (frame_index == 16'd33)
                    tcp_sum <= tcp_sum +
                            {16'd0, dst_ip_work[7:0], gmii_rxd};

                // First TCP byte: seed checksum with the IPv4 pseudo-header.
                if ((frame_index == tcp_start_index) && protocol_ok) begin
                    tcp_started      <= 1'b1;
                    tcp_bytes_seen   <= 16'd1;
                    tcp_sum          <= tcp_sum + 32'h0000_0006 +
                                     {16'd0, tcp_length};
                    tcp_high_byte    <= gmii_rxd;
                    tcp_pair_pending <= 1'b1;
                    src_port_work[15:8] <= gmii_rxd;
                end
                else if (tcp_started && (tcp_bytes_seen < tcp_length)) begin
                    if (tcp_pair_pending) begin
                        tcp_sum          <= tcp_sum + {16'd0, tcp_high_byte, gmii_rxd};
                        tcp_pair_pending <= 1'b0;
                    end
                    else begin
                        tcp_high_byte    <= gmii_rxd;
                        tcp_pair_pending <= 1'b1;
                    end

                    if (mac_ok && eth_ok && ipv4_ok && protocol_ok && ip_dest_ok && fragment_ok && port_ok &&
                            (tcp_header_bytes >= 8'd20) && (tcp_bytes_seen >= {8'd0, tcp_header_bytes}) && ((tcp_bytes_seen - {8'd0, tcp_header_bytes}) < MAX_PAYLOAD)) begin
                        payload_wr_en   <= 1'b1;
                        payload_wr_addr <= tcp_bytes_seen[10:0] - {3'd0, tcp_header_bytes};
                        payload_wr_data <= gmii_rxd;
                    end

                    case (tcp_bytes_seen)
                        16'd1:
                            src_port_work[7:0]  <= gmii_rxd;
                        16'd2:
                            dst_port_work[15:8] <= gmii_rxd;
                        16'd3: begin
                            dst_port_work[7:0] <= gmii_rxd;
                            port_ok <= ({dst_port_work[15:8], gmii_rxd} == LOCAL_PORT);
                        end
                        16'd4, 16'd5, 16'd6, 16'd7:
                            seq_work <= {seq_work[23:0], gmii_rxd};
                        16'd8, 16'd9, 16'd10, 16'd11:
                            ack_work <= {ack_work[23:0], gmii_rxd};
                        16'd12:
                            tcp_header_bytes <= {gmii_rxd[7:4], 2'b00};
                        16'd13:
                            flags_work <= gmii_rxd;
                        16'd14:
                            window_work[15:8] <= gmii_rxd;
                        16'd15:
                            window_work[7:0]  <= gmii_rxd;
                        default:
                            ;
                    endcase
                    tcp_bytes_seen <= tcp_bytes_seen + 1'b1;
                end
            end
        end
        else begin
            preamble_count <= 4'd0;
            if (in_frame) begin
                in_frame         <= 1'b0;
                finalize_pending <= 1'b1;
                candidate_latched <= mac_ok && eth_ok && ipv4_ok && protocol_ok &&
                                  ip_dest_ok && fragment_ok && port_ok && tcp_started;
                if (tcp_pair_pending)
                    tcp_sum_latched <= tcp_sum + {16'd0, tcp_high_byte, 8'd0};
                else
                    tcp_sum_latched <= tcp_sum;
            end
        end
    end
end

endmodule
