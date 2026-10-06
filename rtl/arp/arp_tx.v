`timescale 1ns / 1ps

module arp_tx #(
    parameter [47:0] BOARD_MAC = 48'h00_11_22_33_44_55,
    parameter [31:0] BOARD_IP  = {8'd192, 8'd168, 8'd1, 8'd10},
    parameter [47:0] DES_MAC   = 48'hFF_FF_FF_FF_FF_FF,
    parameter [31:0] DES_IP    = {8'd192, 8'd168, 8'd1, 8'd102}
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        arp_tx_en,
    input  wire        arp_tx_type,
    input  wire [47:0] des_mac,
    input  wire [31:0] des_ip,
    input  wire [31:0] crc_data,
    input  wire [7:0]  crc_next,
    output reg         tx_done,
    output reg         gmii_tx_en,
    output reg  [7:0]  gmii_txd,
    output reg         crc_en,
    output reg         crc_clr
);

localparam [2:0] TX_IDLE     = 3'd0;
localparam [2:0] TX_PREAMBLE = 3'd1;
localparam [2:0] TX_FRAME    = 3'd2;
localparam [2:0] TX_FCS      = 3'd3;

reg [2:0]  state;
reg [6:0]  byte_index;
reg        reply_latched;
reg [47:0] peer_mac;
reg [31:0] peer_ip;

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
    input [6:0] index;
    reg [47:0] ethernet_destination;
    reg [47:0] target_hardware;
    begin
        ethernet_destination = reply_latched ? peer_mac : 48'hFF_FF_FF_FF_FF_FF;
        target_hardware      = reply_latched ? peer_mac : 48'd0;

        if (index < 6)
            frame_byte = selected_byte48(ethernet_destination, index[2:0]);
        else if (index < 12)
            frame_byte = selected_byte48(BOARD_MAC, index - 6);
        else begin
            case (index)
                12: frame_byte = 8'h08;
                13: frame_byte = 8'h06;
                14: frame_byte = 8'h00;
                15: frame_byte = 8'h01;
                16: frame_byte = 8'h08;
                17: frame_byte = 8'h00;
                18: frame_byte = 8'h06;
                19: frame_byte = 8'h04;
                20: frame_byte = 8'h00;
                21: frame_byte = reply_latched ? 8'h02 : 8'h01;
                22,23,24,25,26,27:
                    frame_byte = selected_byte48(BOARD_MAC, index - 22);
                28,29,30,31:
                    frame_byte = selected_byte32(BOARD_IP, index - 28);
                32,33,34,35,36,37:
                    frame_byte = selected_byte48(target_hardware, index - 32);
                38,39,40,41:
                    frame_byte = selected_byte32(peer_ip, index - 38);
                default: frame_byte = 8'h00;
            endcase
        end
    end
endfunction

always @(*) begin
    gmii_tx_en = 1'b0;
    gmii_txd   = 8'h00;
    crc_en     = 1'b0;
    crc_clr    = 1'b0;

    case (state)
        TX_IDLE: begin
            crc_clr = 1'b1;
        end
        TX_PREAMBLE: begin
            gmii_tx_en = 1'b1;
            crc_clr    = 1'b1;
            gmii_txd   = (byte_index == 7) ? 8'hD5 : 8'h55;
        end
        TX_FRAME: begin
            gmii_tx_en = 1'b1;
            gmii_txd   = frame_byte(byte_index);
            crc_en     = 1'b1;
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
        state          <= TX_IDLE;
        byte_index     <= 7'd0;
        reply_latched  <= 1'b0;
        peer_mac       <= DES_MAC;
        peer_ip        <= DES_IP;
        tx_done        <= 1'b0;
    end else begin
        tx_done <= 1'b0;

        case (state)
            TX_IDLE: begin
                byte_index <= 7'd0;
                if (arp_tx_en) begin
                    reply_latched <= arp_tx_type;
                    peer_mac      <= (des_mac == 48'd0) ? DES_MAC : des_mac;
                    peer_ip       <= (des_ip == 32'd0) ? DES_IP : des_ip;
                    state         <= TX_PREAMBLE;
                end
            end

            TX_PREAMBLE: begin
                if (byte_index == 7) begin
                    byte_index <= 7'd0;
                    state      <= TX_FRAME;
                end else begin
                    byte_index <= byte_index + 1'b1;
                end
            end

            TX_FRAME: begin
                if (byte_index == 59) begin
                    byte_index <= 7'd0;
                    state      <= TX_FCS;
                end else begin
                    byte_index <= byte_index + 1'b1;
                end
            end

            TX_FCS: begin
                if (byte_index == 3) begin
                    byte_index <= 7'd0;
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

// Kept for drop-in compatibility with the previous module interface.
wire unused_crc_next = &{1'b0, crc_next};

endmodule

