`timescale 1ns / 1ps

module icmp_tx #(
    parameter [47:0] BOARD_MAC = 48'h00_11_22_33_44_55,
    parameter [31:0] BOARD_IP  = {8'd192, 8'd168, 8'd1, 8'd10},
    parameter [47:0] DES_MAC   = 48'hFF_FF_FF_FF_FF_FF,
    parameter [31:0] DES_IP    = {8'd192, 8'd168, 8'd1, 8'd102}
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] reply_checksum,
    input  wire [15:0] icmp_id,
    input  wire [15:0] icmp_seq,
    input  wire        tx_start_en,
    input  wire [7:0]  tx_data,
    input  wire [15:0] tx_byte_num,
    input  wire [47:0] des_mac,
    input  wire [31:0] des_ip,
    input  wire [31:0] crc_data,
    input  wire [7:0]  crc_next,
    output reg         tx_done,
    output reg         tx_req,
    output reg         gmii_tx_en,
    output reg  [7:0]  gmii_txd,
    output reg         crc_en,
    output reg         crc_clr
);

localparam [2:0] TX_IDLE       = 3'd0;
localparam [2:0] TX_SUM_GROUPS = 3'd1;
localparam [2:0] TX_SUM_MERGE  = 3'd2;
localparam [2:0] TX_SUM_FOLD   = 3'd3;
localparam [2:0] TX_SUM_FINAL  = 3'd4;
localparam [2:0] TX_PREAMBLE   = 3'd5;
localparam [2:0] TX_FRAME      = 3'd6;
localparam [2:0] TX_FCS        = 3'd7;

reg [2:0]  state;
reg [15:0] byte_index;
reg [47:0] peer_mac;
reg [31:0] peer_ip;
reg [15:0] payload_bytes;
reg [15:0] frame_bytes;
reg [15:0] packet_id;
reg [15:0] identification_counter;
reg [15:0] id_latched;
reg [15:0] sequence_latched;
reg [15:0] ip_checksum;
reg [15:0] echo_checksum;
reg [31:0] ip_sum_a;
reg [31:0] ip_sum_b;
reg [31:0] ip_sum;
reg [31:0] echo_sum;
reg [31:0] payload_sum_latched;

function [7:0] selected_byte48;
    input [47:0] value;
    input [2:0]  index;
    begin
        case (index)
            0: selected_byte48 = value[47:40];
            1: selected_byte48 = value[39:32];
            2: selected_byte48 = value[31:24];
            3: selected_byte48 = value[23:16];
            4: selected_byte48 = value[15:8];
            default: selected_byte48 = value[7:0];
        endcase
    end
endfunction

function [7:0] selected_byte32;
    input [31:0] value;
    input [1:0]  index;
    begin
        case (index)
            0: selected_byte32 = value[31:24];
            1: selected_byte32 = value[23:16];
            2: selected_byte32 = value[15:8];
            default: selected_byte32 = value[7:0];
        endcase
    end
endfunction

function [7:0] frame_byte;
    input [15:0] index;
    reg [15:0] ip_length;
    begin
        ip_length = payload_bytes + 16'd28;
        if (index < 6)
            frame_byte = selected_byte48(peer_mac, index[2:0]);
        else if (index < 12)
            frame_byte = selected_byte48(BOARD_MAC, index - 6);
        else begin
            case (index)
                12: frame_byte = 8'h08;
                13: frame_byte = 8'h00;
                14: frame_byte = 8'h45;
                15: frame_byte = 8'h00;
                16: frame_byte = ip_length[15:8];
                17: frame_byte = ip_length[7:0];
                18: frame_byte = packet_id[15:8];
                19: frame_byte = packet_id[7:0];
                20: frame_byte = 8'h40;
                21: frame_byte = 8'h00;
                22: frame_byte = 8'h40;
                23: frame_byte = 8'h01;
                24: frame_byte = ip_checksum[15:8];
                25: frame_byte = ip_checksum[7:0];
                26,27,28,29:
                    frame_byte = selected_byte32(BOARD_IP, index - 26);
                30,31,32,33:
                    frame_byte = selected_byte32(peer_ip, index - 30);
                34: frame_byte = 8'h00;
                35: frame_byte = 8'h00;
                36: frame_byte = echo_checksum[15:8];
                37: frame_byte = echo_checksum[7:0];
                38: frame_byte = id_latched[15:8];
                39: frame_byte = id_latched[7:0];
                40: frame_byte = sequence_latched[15:8];
                41: frame_byte = sequence_latched[7:0];
                default: begin
                    if ((index >= 42) && (index < (16'd42 + payload_bytes)))
                        frame_byte = tx_data;
                    else
                        frame_byte = 8'h00;
                end
            endcase
        end
    end
endfunction

always @(*) begin
    gmii_tx_en = 1'b0;
    gmii_txd   = 8'h00;
    tx_req     = 1'b0;
    crc_en     = 1'b0;
    crc_clr    = 1'b0;

    case (state)
        TX_IDLE,
        TX_SUM_GROUPS,
        TX_SUM_MERGE,
        TX_SUM_FOLD,
        TX_SUM_FINAL: crc_clr = 1'b1;

        TX_PREAMBLE: begin
            gmii_tx_en = 1'b1;
            crc_clr    = 1'b1;
            gmii_txd   = (byte_index == 7) ? 8'hD5 : 8'h55;
        end

        TX_FRAME: begin
            gmii_tx_en = 1'b1;
            gmii_txd   = frame_byte(byte_index);
            crc_en     = 1'b1;
            tx_req     = (byte_index >= 42) &&
                         (byte_index < (16'd42 + payload_bytes));
        end

        TX_FCS: begin
            gmii_tx_en = 1'b1;
            case (byte_index[1:0])
                2'd0: gmii_txd = ~crc_data[7:0];
                2'd1: gmii_txd = ~crc_data[15:8];
                2'd2: gmii_txd = ~crc_data[23:16];
                default: gmii_txd = ~crc_data[31:24];
            endcase
        end

        default: ;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                  <= TX_IDLE;
        byte_index             <= 16'd0;
        peer_mac               <= DES_MAC;
        peer_ip                <= DES_IP;
        payload_bytes          <= 16'd0;
        frame_bytes            <= 16'd60;
        packet_id              <= 16'd0;
        identification_counter <= 16'd0;
        id_latched             <= 16'd0;
        sequence_latched       <= 16'd0;
        ip_checksum            <= 16'd0;
        echo_checksum          <= 16'd0;
        ip_sum_a               <= 32'd0;
        ip_sum_b               <= 32'd0;
        ip_sum                 <= 32'd0;
        echo_sum               <= 32'd0;
        payload_sum_latched    <= 32'd0;
        tx_done                <= 1'b0;
    end else begin
        tx_done <= 1'b0;

        case (state)
            TX_IDLE: begin
                byte_index <= 16'd0;
                if (tx_start_en) begin
                    peer_mac         <= (des_mac == 48'd0) ? DES_MAC : des_mac;
                    peer_ip          <= (des_ip == 32'd0) ? DES_IP : des_ip;
                    payload_bytes    <= tx_byte_num;
                    frame_bytes      <= ((16'd42 + tx_byte_num) < 16'd60) ?
                                        16'd60 : (16'd42 + tx_byte_num);
                    packet_id        <= identification_counter;
                    id_latched       <= icmp_id;
                    sequence_latched <= icmp_seq;
                    payload_sum_latched <= reply_checksum;
                    identification_counter <= identification_counter + 1'b1;
                    state <= TX_SUM_GROUPS;
                end
            end

            TX_SUM_GROUPS: begin
                // Split the checksum tree into small groups so it closes at
                // 125 MHz without changing the packet contents.
                ip_sum_a <= 32'h0000_4500 + (payload_bytes + 16'd28) +
                            packet_id + 16'h4000;
                ip_sum_b <= 32'h0000_4001 + BOARD_IP[31:16] +
                            BOARD_IP[15:0] + peer_ip[31:16] + peer_ip[15:0];
                echo_sum <= payload_sum_latched + id_latched + sequence_latched;
                state <= TX_SUM_MERGE;
            end

            TX_SUM_MERGE: begin
                ip_sum   <= ip_sum_a + ip_sum_b;
                echo_sum <= echo_sum[31:16] + echo_sum[15:0];
                state    <= TX_SUM_FOLD;
            end

            TX_SUM_FOLD: begin
                ip_sum   <= ip_sum[31:16] + ip_sum[15:0];
                echo_sum <= echo_sum[31:16] + echo_sum[15:0];
                state    <= TX_SUM_FINAL;
            end

            TX_SUM_FINAL: begin
                ip_checksum   <= ~(ip_sum[31:16] + ip_sum[15:0]);
                echo_checksum <= ~(echo_sum[31:16] + echo_sum[15:0]);
                byte_index    <= 16'd0;
                state         <= TX_PREAMBLE;
            end

            TX_PREAMBLE: begin
                if (byte_index == 7) begin
                    byte_index <= 16'd0;
                    state      <= TX_FRAME;
                end else begin
                    byte_index <= byte_index + 1'b1;
                end
            end

            TX_FRAME: begin
                if (byte_index == frame_bytes - 1'b1) begin
                    byte_index <= 16'd0;
                    state      <= TX_FCS;
                end else begin
                    byte_index <= byte_index + 1'b1;
                end
            end

            TX_FCS: begin
                if (byte_index == 3) begin
                    byte_index <= 16'd0;
                    state      <= TX_IDLE;
                    tx_done    <= 1'b1;
                end else begin
                    byte_index <= byte_index + 1'b1;
                end
            end

            default: state <= TX_IDLE;
        endcase
    end
end

wire unused_crc_next = &{1'b0, crc_next};

endmodule
