`timescale 1ns / 1ps

module arp_rx #(
    parameter [47:0] BOARD_MAC = 48'h00_11_22_33_44_55,
    parameter [31:0] BOARD_IP  = {8'd192, 8'd168, 8'd1, 8'd10}
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        gmii_rx_dv,
    input  wire [7:0]  gmii_rxd,
    output reg         arp_rx_done,
    output reg         arp_rx_type,
    output reg  [47:0] src_mac,
    output reg  [31:0] src_ip
);

localparam [2:0] RX_IDLE     = 3'd0;
localparam [2:0] RX_PREAMBLE = 3'd1;
localparam [2:0] RX_ETHERNET = 3'd2;
localparam [2:0] RX_ARP      = 3'd3;
localparam [2:0] RX_DROP     = 3'd4;

reg [2:0]  state;
reg [5:0]  byte_index;
reg [47:0] destination_mac;
reg [15:0] ether_type;
reg [15:0] hardware_type;
reg [15:0] protocol_type;
reg [7:0]  hardware_length;
reg [7:0]  protocol_length;
reg [15:0] operation;
reg [47:0] sender_mac;
reg [31:0] sender_ip;
reg [31:0] target_ip;

wire destination_matches = (destination_mac == BOARD_MAC) ||
                           (destination_mac == 48'hFF_FF_FF_FF_FF_FF);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state           <= RX_IDLE;
        byte_index      <= 6'd0;
        destination_mac <= 48'd0;
        ether_type      <= 16'd0;
        hardware_type   <= 16'd0;
        protocol_type   <= 16'd0;
        hardware_length <= 8'd0;
        protocol_length <= 8'd0;
        operation       <= 16'd0;
        sender_mac      <= 48'd0;
        sender_ip       <= 32'd0;
        target_ip       <= 32'd0;
        arp_rx_done     <= 1'b0;
        arp_rx_type     <= 1'b0;
        src_mac         <= 48'd0;
        src_ip          <= 32'd0;
    end else begin
        arp_rx_done <= 1'b0;

        case (state)
            RX_IDLE: begin
                byte_index <= 6'd0;
                if (gmii_rx_dv && (gmii_rxd == 8'h55)) begin
                    state      <= RX_PREAMBLE;
                    byte_index <= 6'd0;
                end
            end

            RX_PREAMBLE: begin
                if (!gmii_rx_dv) begin
                    state <= RX_IDLE;
                end else if (byte_index < 6) begin
                    if (gmii_rxd != 8'h55)
                        state <= RX_DROP;
                    else
                        byte_index <= byte_index + 1'b1;
                end else if (gmii_rxd == 8'hD5) begin
                    state           <= RX_ETHERNET;
                    byte_index      <= 6'd0;
                    destination_mac <= 48'd0;
                    ether_type      <= 16'd0;
                end else begin
                    state <= RX_DROP;
                end
            end

            RX_ETHERNET: begin
                if (!gmii_rx_dv) begin
                    state <= RX_IDLE;
                end else begin
                    if (byte_index < 6)
                        destination_mac <= {destination_mac[39:0], gmii_rxd};
                    if (byte_index == 12)
                        ether_type[15:8] <= gmii_rxd;

                    if (byte_index == 13) begin
                        ether_type[7:0] <= gmii_rxd;
                        byte_index      <= 6'd0;
                        if (destination_matches &&
                            (ether_type[15:8] == 8'h08) &&
                            (gmii_rxd == 8'h06)) begin
                            state           <= RX_ARP;
                            hardware_type   <= 16'd0;
                            protocol_type   <= 16'd0;
                            hardware_length <= 8'd0;
                            protocol_length <= 8'd0;
                            operation       <= 16'd0;
                            sender_mac      <= 48'd0;
                            sender_ip       <= 32'd0;
                            target_ip       <= 32'd0;
                        end else begin
                            state <= RX_DROP;
                        end
                    end else begin
                        byte_index <= byte_index + 1'b1;
                    end
                end
            end

            RX_ARP: begin
                if (!gmii_rx_dv) begin
                    state <= RX_IDLE;
                end else begin
                    case (byte_index)
                        0:  hardware_type[15:8] <= gmii_rxd;
                        1:  hardware_type[7:0]  <= gmii_rxd;
                        2:  protocol_type[15:8] <= gmii_rxd;
                        3:  protocol_type[7:0]  <= gmii_rxd;
                        4:  hardware_length     <= gmii_rxd;
                        5:  protocol_length     <= gmii_rxd;
                        6:  operation[15:8]     <= gmii_rxd;
                        7:  operation[7:0]      <= gmii_rxd;
                        8,9,10,11,12,13:
                            sender_mac <= {sender_mac[39:0], gmii_rxd};
                        14,15,16,17:
                            sender_ip <= {sender_ip[23:0], gmii_rxd};
                        24,25,26:
                            target_ip <= {target_ip[23:0], gmii_rxd};
                        27: begin
                            target_ip <= {target_ip[23:0], gmii_rxd};
                            if ((hardware_type == 16'h0001) &&
                                (protocol_type == 16'h0800) &&
                                (hardware_length == 8'd6) &&
                                (protocol_length == 8'd4) &&
                                ((operation == 16'h0001) ||
                                 (operation == 16'h0002)) &&
                                ({target_ip[23:0], gmii_rxd} == BOARD_IP)) begin
                                src_mac     <= sender_mac;
                                src_ip      <= sender_ip;
                                arp_rx_type <= (operation == 16'h0002);
                                arp_rx_done <= 1'b1;
                            end
                            state <= RX_DROP;
                        end
                        default: ;
                    endcase

                    if (byte_index != 27)
                        byte_index <= byte_index + 1'b1;
                end
            end

            RX_DROP: begin
                if (!gmii_rx_dv)
                    state <= RX_IDLE;
            end

            default: state <= RX_IDLE;
        endcase
    end
end

endmodule

