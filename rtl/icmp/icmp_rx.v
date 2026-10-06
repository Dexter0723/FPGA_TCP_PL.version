`timescale 1ns / 1ps

module icmp_rx #(
    parameter [47:0] BOARD_MAC = 48'h00_11_22_33_44_55,
    parameter [31:0] BOARD_IP  = {8'd192, 8'd168, 8'd1, 8'd10}
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        gmii_rx_dv,
    input  wire [7:0]  gmii_rxd,
    output reg         rec_pkt_done,
    output reg         rec_en,
    output reg  [7:0]  rec_data,
    output reg  [15:0] rec_byte_num,
    output reg  [15:0] icmp_id,
    output reg  [15:0] icmp_seq,
    output reg  [31:0] reply_checksum
);

localparam [3:0] RX_IDLE       = 4'd0;
localparam [3:0] RX_PREAMBLE   = 4'd1;
localparam [3:0] RX_ETHERNET   = 4'd2;
localparam [3:0] RX_IP_HEADER  = 4'd3;
localparam [3:0] RX_IP_OPTIONS = 4'd4;
localparam [3:0] RX_ICMP       = 4'd5;
localparam [3:0] RX_PAYLOAD    = 4'd6;
localparam [3:0] RX_DROP       = 4'd7;

reg [3:0]  state;
reg [7:0]  byte_index;
reg [47:0] destination_mac;
reg [15:0] ether_type;
reg [7:0]  ip_header_bytes;
reg [15:0] ip_total_length;
reg [15:0] fragment_field;
reg [7:0]  ip_protocol;
reg [31:0] destination_ip;
reg [7:0]  option_bytes_left;
reg [7:0]  icmp_type;
reg [7:0]  icmp_code;
reg [15:0] payload_length;
reg [15:0] payload_index;
reg [7:0]  payload_high_byte;
reg [31:0] payload_sum;

wire destination_matches = (destination_mac == BOARD_MAC) ||
                           (destination_mac == 48'hFF_FF_FF_FF_FF_FF);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state               <= RX_IDLE;
        byte_index          <= 8'd0;
        destination_mac     <= 48'd0;
        ether_type          <= 16'd0;
        ip_header_bytes     <= 8'd20;
        ip_total_length     <= 16'd0;
        fragment_field      <= 16'd0;
        ip_protocol         <= 8'd0;
        destination_ip      <= 32'd0;
        option_bytes_left   <= 8'd0;
        icmp_type           <= 8'd0;
        icmp_code           <= 8'd0;
        payload_length      <= 16'd0;
        payload_index       <= 16'd0;
        payload_high_byte   <= 8'd0;
        payload_sum         <= 32'd0;
        rec_pkt_done        <= 1'b0;
        rec_en              <= 1'b0;
        rec_data            <= 8'd0;
        rec_byte_num        <= 16'd0;
        icmp_id             <= 16'd0;
        icmp_seq            <= 16'd0;
        reply_checksum      <= 32'd0;
    end else begin
        rec_pkt_done <= 1'b0;
        rec_en       <= 1'b0;

        case (state)
            RX_IDLE: begin
                byte_index <= 8'd0;
                if (gmii_rx_dv && (gmii_rxd == 8'h55)) begin
                    state      <= RX_PREAMBLE;
                    byte_index <= 8'd0;
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
                    byte_index      <= 8'd0;
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
                        byte_index <= 8'd0;
                        if (destination_matches &&
                            (ether_type[15:8] == 8'h08) &&
                            (gmii_rxd == 8'h00)) begin
                            state             <= RX_IP_HEADER;
                            ip_header_bytes   <= 8'd20;
                            ip_total_length   <= 16'd0;
                            fragment_field    <= 16'd0;
                            ip_protocol       <= 8'd0;
                            destination_ip    <= 32'd0;
                        end else begin
                            state <= RX_DROP;
                        end
                    end else begin
                        byte_index <= byte_index + 1'b1;
                    end
                end
            end

            RX_IP_HEADER: begin
                if (!gmii_rx_dv) begin
                    state <= RX_IDLE;
                end else begin
                    case (byte_index)
                        0: begin
                            if ((gmii_rxd[7:4] != 4'd4) || (gmii_rxd[3:0] < 4'd5))
                                state <= RX_DROP;
                            ip_header_bytes <= {gmii_rxd[3:0], 2'b00};
                        end
                        2: ip_total_length[15:8] <= gmii_rxd;
                        3: ip_total_length[7:0]  <= gmii_rxd;
                        6: fragment_field[15:8]  <= gmii_rxd;
                        7: fragment_field[7:0]   <= gmii_rxd;
                        9: ip_protocol           <= gmii_rxd;
                        16,17,18:
                            destination_ip <= {destination_ip[23:0], gmii_rxd};
                        19: begin
                            destination_ip <= {destination_ip[23:0], gmii_rxd};
                            byte_index     <= 8'd0;
                            if ((ip_protocol != 8'd1) ||
                                ((fragment_field & 16'h3FFF) != 16'd0) ||
                                ({destination_ip[23:0], gmii_rxd} != BOARD_IP) ||
                                (ip_total_length < ({8'd0, ip_header_bytes} + 16'd8))) begin
                                state <= RX_DROP;
                            end else if (ip_header_bytes > 8'd20) begin
                                option_bytes_left <= ip_header_bytes - 8'd20;
                                state <= RX_IP_OPTIONS;
                            end else begin
                                state <= RX_ICMP;
                                icmp_type <= 8'd0;
                                icmp_code <= 8'd0;
                            end
                        end
                        default: ;
                    endcase

                    if (byte_index != 19)
                        byte_index <= byte_index + 1'b1;
                end
            end

            RX_IP_OPTIONS: begin
                if (!gmii_rx_dv) begin
                    state <= RX_IDLE;
                end else if (option_bytes_left == 1) begin
                    option_bytes_left <= 8'd0;
                    byte_index        <= 8'd0;
                    icmp_type         <= 8'd0;
                    icmp_code         <= 8'd0;
                    state             <= RX_ICMP;
                end else begin
                    option_bytes_left <= option_bytes_left - 1'b1;
                end
            end

            RX_ICMP: begin
                if (!gmii_rx_dv) begin
                    state <= RX_IDLE;
                end else begin
                    case (byte_index)
                        0: icmp_type     <= gmii_rxd;
                        1: icmp_code     <= gmii_rxd;
                        4: icmp_id[15:8] <= gmii_rxd;
                        5: icmp_id[7:0]  <= gmii_rxd;
                        6: icmp_seq[15:8] <= gmii_rxd;
                        7: begin
                            icmp_seq[7:0] <= gmii_rxd;
                            payload_length <= ip_total_length -
                                              {8'd0, ip_header_bytes} - 16'd8;
                            payload_index     <= 16'd0;
                            payload_high_byte <= 8'd0;
                            payload_sum       <= 32'd0;
                            byte_index        <= 8'd0;

                            if ((icmp_type != 8'h08) || (icmp_code != 8'h00) ||
                                ((ip_total_length - {8'd0, ip_header_bytes} - 16'd8) > 16'd2048)) begin
                                state <= RX_DROP;
                            end else if ((ip_total_length - {8'd0, ip_header_bytes} - 16'd8) == 0) begin
                                rec_byte_num   <= 16'd0;
                                reply_checksum <= 32'd0;
                                rec_pkt_done   <= 1'b1;
                                state          <= RX_DROP;
                            end else begin
                                state <= RX_PAYLOAD;
                            end
                        end
                        default: ;
                    endcase

                    if (byte_index != 7)
                        byte_index <= byte_index + 1'b1;
                end
            end

            RX_PAYLOAD: begin
                if (!gmii_rx_dv) begin
                    state <= RX_IDLE;
                end else begin
                    rec_en   <= 1'b1;
                    rec_data <= gmii_rxd;

                    if (!payload_index[0])
                        payload_high_byte <= gmii_rxd;
                    else
                        payload_sum <= payload_sum + {payload_high_byte, gmii_rxd};

                    if (payload_index == payload_length - 1'b1) begin
                        rec_byte_num <= payload_length;
                        if (payload_index[0])
                            reply_checksum <= payload_sum + {payload_high_byte, gmii_rxd};
                        else
                            reply_checksum <= payload_sum + {gmii_rxd, 8'h00};
                        rec_pkt_done <= 1'b1;
                        state        <= RX_DROP;
                    end else begin
                        payload_index <= payload_index + 1'b1;
                    end
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

