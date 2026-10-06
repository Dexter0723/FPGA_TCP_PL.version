`timescale 1ns / 1ps

// Ethernet/IPv4/TCP frame transmitter. One byte is emitted every 125 MHz
// GMII clock while a frame is active. Preamble, minimum-frame padding, FCS,
// and the 12-byte inter-frame gap are generated in hardware.
module tcp_tx #(
           parameter [47:0] LOCAL_MAC  = 48'h00_11_22_33_44_55,
           parameter [31:0] LOCAL_IP   = {8'd192, 8'd168, 8'd1, 8'd10},
           parameter [15:0] LOCAL_PORT = 16'd5000,
           parameter        RAM_ADDR_WIDTH = 16
       )(
           input  wire                       clk,
           input  wire                       rst_n,
           input  wire                       tx_start,
           input  wire [47:0]                remote_mac,
           input  wire [31:0]                remote_ip,
           input  wire [15:0]                remote_port,
           input  wire [31:0]                sequence_number,
           input  wire [31:0]                acknowledgment_number,
           input  wire [7:0]                 tcp_flags,
           input  wire [15:0]                local_window,
           input  wire [15:0]                payload_length,
           input  wire [RAM_ADDR_WIDTH-1:0]  payload_start,
           input  wire [31:0]                payload_sum,
           input  wire [15:0]                ip_identification,

           output reg  [RAM_ADDR_WIDTH-1:0]  payload_rd_addr,
           input  wire [7:0]                 payload_rd_data,

           output reg                        busy,
           output reg                        tx_done,
           output reg                        gmii_tx_en,
           output reg  [7:0]                 gmii_txd
       );

localparam [3:0] ST_IDLE     = 4'd0;
localparam [3:0] ST_PREAMBLE = 4'd1;
localparam [3:0] ST_ETH      = 4'd2;
localparam [3:0] ST_IP       = 4'd3;
localparam [3:0] ST_TCP      = 4'd4;
localparam [3:0] ST_PAYLOAD  = 4'd5;
localparam [3:0] ST_PAD      = 4'd6;
localparam [3:0] ST_FCS      = 4'd7;
localparam [3:0] ST_IFG      = 4'd8;
localparam [3:0] ST_PREP     = 4'd9;

reg [3:0]  state;
reg [7:0]  byte_count;
reg [15:0] payload_count;
reg [4:0]  ifg_count;
reg [7:0]  pad_length;
reg [3:0]  prep_count;

reg [47:0] remote_mac_latched;
reg [31:0] remote_ip_latched;
reg [15:0] remote_port_latched;
reg [31:0] seq_latched;
reg [31:0] ack_latched;
reg [7:0]  flags_latched;
reg [15:0] window_latched;
reg [15:0] payload_length_latched;
reg [RAM_ADDR_WIDTH-1:0] payload_start_latched;
reg [15:0] ip_id_latched;
reg [15:0] ip_total_length;
reg [15:0] ip_checksum;
reg [15:0] tcp_checksum;
reg [31:0] ip_sum_work;
reg [31:0] tcp_sum_work;

reg         crc_en;
reg         crc_clr;
wire [31:0] crc_data;
wire [31:0] crc_next;

crc32_d8 u_crc32_d8 (
             .clk      (clk),
             .rst_n    (rst_n),
             .data     (gmii_txd),
             .crc_en   (crc_en),
             .crc_clr  (crc_clr),
             .crc_data (crc_data),
             .crc_next (crc_next)
         );

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                   <= ST_IDLE;
        byte_count              <= 8'd0;
        payload_count           <= 16'd0;
        ifg_count               <= 5'd0;
        pad_length              <= 8'd0;
        prep_count              <= 4'd0;
        remote_mac_latched      <= 48'd0;
        remote_ip_latched       <= 32'd0;
        remote_port_latched     <= 16'd0;
        seq_latched             <= 32'd0;
        ack_latched             <= 32'd0;
        flags_latched           <= 8'd0;
        window_latched          <= 16'd0;
        payload_length_latched  <= 16'd0;
        payload_start_latched   <= {RAM_ADDR_WIDTH{1'b0}};
        ip_id_latched           <= 16'd0;
        ip_total_length         <= 16'd40;
        ip_checksum             <= 16'd0;
        tcp_checksum            <= 16'd0;
        ip_sum_work             <= 32'd0;
        tcp_sum_work            <= 32'd0;
        payload_rd_addr         <= {RAM_ADDR_WIDTH{1'b0}};
        busy                    <= 1'b0;
        tx_done                 <= 1'b0;
        gmii_tx_en              <= 1'b0;
        gmii_txd                <= 8'd0;
        crc_en                  <= 1'b0;
        crc_clr                 <= 1'b1;
    end
    else begin
        tx_done <= 1'b0;
        crc_clr <= 1'b0;

        case (state)
            ST_IDLE: begin
                busy       <= 1'b0;
                gmii_tx_en <= 1'b0;
                gmii_txd   <= 8'd0;
                crc_en     <= 1'b0;
                byte_count <= 8'd0;
                if (tx_start) begin
                    busy                   <= 1'b1;
                    state                  <= ST_PREP;
                    prep_count             <= 4'd0;
                    remote_mac_latched     <= remote_mac;
                    remote_ip_latched      <= remote_ip;
                    remote_port_latched    <= remote_port;
                    seq_latched            <= sequence_number;
                    ack_latched            <= acknowledgment_number;
                    flags_latched          <= tcp_flags;
                    window_latched         <= local_window;
                    payload_length_latched <= payload_length;
                    payload_start_latched  <= payload_start;
                    ip_id_latched          <= ip_identification;
                    ip_total_length        <= 16'd40 + payload_length;
                    if ((16'd40 + payload_length) < 16'd46)
                        pad_length <= 16'd46 - (16'd40 + payload_length);
                    else
                        pad_length <= 8'd0;

                    // Start the checksum accumulators here, then finish them
                    // over several clocks in ST_PREP.  The staged adder is
                    // intentionally short enough to meet 125 MHz timing.
                    ip_sum_work  <= 32'h0000_4500 +
                    {16'd0, (16'd40 + payload_length)};
                    tcp_sum_work <= payload_sum +
                    {16'd0, LOCAL_IP[31:16]};
                end
            end

            ST_PREP: begin
                gmii_tx_en <= 1'b0;
                gmii_txd   <= 8'd0;
                crc_en     <= 1'b0;

                case (prep_count)
                    4'd0: begin
                        ip_sum_work  <= ip_sum_work +
                        {16'd0, ip_id_latched} + 32'h0000_4000;
                        tcp_sum_work <= tcp_sum_work +
                        {16'd0, LOCAL_IP[15:0]} +
                        {16'd0, remote_ip_latched[31:16]};
                    end
                    4'd1: begin
                        ip_sum_work  <= ip_sum_work + 32'h0000_4006 +
                        {16'd0, LOCAL_IP[31:16]};
                        tcp_sum_work <= tcp_sum_work +
                        {16'd0, remote_ip_latched[15:0]} +
                        32'h0000_0006;
                    end
                    4'd2: begin
                        ip_sum_work  <= ip_sum_work +
                        {16'd0, LOCAL_IP[15:0]} +
                        {16'd0, remote_ip_latched[31:16]};
                        tcp_sum_work <= tcp_sum_work +
                        {16'd0, (16'd20 + payload_length_latched)} +
                        {16'd0, LOCAL_PORT};
                    end
                    4'd3: begin
                        ip_sum_work  <= ip_sum_work +
                        {16'd0, remote_ip_latched[15:0]};
                        tcp_sum_work <= tcp_sum_work +
                        {16'd0, remote_port_latched} +
                        {16'd0, seq_latched[31:16]};
                    end
                    4'd4: begin
                        tcp_sum_work <= tcp_sum_work +
                        {16'd0, seq_latched[15:0]} +
                        {16'd0, ack_latched[31:16]};
                    end
                    4'd5: begin
                        tcp_sum_work <= tcp_sum_work +
                        {16'd0, ack_latched[15:0]} +
                        {16'd0, (16'h5000 | {8'd0, flags_latched})};
                    end
                    4'd6: begin
                        tcp_sum_work <= tcp_sum_work +
                        {16'd0, window_latched};
                    end
                    4'd7: begin
                        ip_sum_work  <= {16'd0, ip_sum_work[31:16]} +
                        {16'd0, ip_sum_work[15:0]};
                        tcp_sum_work <= {16'd0, tcp_sum_work[31:16]} +
                        {16'd0, tcp_sum_work[15:0]};
                    end
                    4'd8: begin
                        ip_sum_work  <= {16'd0, ip_sum_work[31:16]} +
                        {16'd0, ip_sum_work[15:0]};
                        tcp_sum_work <= {16'd0, tcp_sum_work[31:16]} +
                        {16'd0, tcp_sum_work[15:0]};
                    end
                    default: begin
                        ip_checksum  <= ~ip_sum_work[15:0];
                        tcp_checksum <= ~tcp_sum_work[15:0];
                        byte_count   <= 8'd0;
                        state        <= ST_PREAMBLE;
                    end
                endcase

                if (prep_count != 4'd9)
                    prep_count <= prep_count + 1'b1;
            end

            ST_PREAMBLE: begin
                gmii_tx_en <= 1'b1;
                crc_en     <= 1'b0;
                gmii_txd   <= (byte_count == 8'd7) ? 8'hd5 : 8'h55;
                if (byte_count == 8'd7) begin
                    byte_count <= 8'd0;
                    state      <= ST_ETH;
                end
                else begin
                    byte_count <= byte_count + 1'b1;
                end
            end

            ST_ETH: begin
                gmii_tx_en <= 1'b1;
                crc_en     <= 1'b1;
                case (byte_count)
                    8'd0:
                        gmii_txd <= remote_mac_latched[47:40];
                    8'd1:
                        gmii_txd <= remote_mac_latched[39:32];
                    8'd2:
                        gmii_txd <= remote_mac_latched[31:24];
                    8'd3:
                        gmii_txd <= remote_mac_latched[23:16];
                    8'd4:
                        gmii_txd <= remote_mac_latched[15:8];
                    8'd5:
                        gmii_txd <= remote_mac_latched[7:0];
                    8'd6:
                        gmii_txd <= LOCAL_MAC[47:40];
                    8'd7:
                        gmii_txd <= LOCAL_MAC[39:32];
                    8'd8:
                        gmii_txd <= LOCAL_MAC[31:24];
                    8'd9:
                        gmii_txd <= LOCAL_MAC[23:16];
                    8'd10:
                        gmii_txd <= LOCAL_MAC[15:8];
                    8'd11:
                        gmii_txd <= LOCAL_MAC[7:0];
                    8'd12:
                        gmii_txd <= 8'h08;
                    default:
                        gmii_txd <= 8'h00;
                endcase
                if (byte_count == 8'd13) begin
                    byte_count <= 8'd0;
                    state      <= ST_IP;
                end
                else begin
                    byte_count <= byte_count + 1'b1;
                end
            end

            ST_IP: begin
                gmii_tx_en <= 1'b1;
                crc_en     <= 1'b1;
                case (byte_count)
                    8'd0:
                        gmii_txd <= 8'h45;
                    8'd1:
                        gmii_txd <= 8'h00;
                    8'd2:
                        gmii_txd <= ip_total_length[15:8];
                    8'd3:
                        gmii_txd <= ip_total_length[7:0];
                    8'd4:
                        gmii_txd <= ip_id_latched[15:8];
                    8'd5:
                        gmii_txd <= ip_id_latched[7:0];
                    8'd6:
                        gmii_txd <= 8'h40;
                    8'd7:
                        gmii_txd <= 8'h00;
                    8'd8:
                        gmii_txd <= 8'h40;
                    8'd9:
                        gmii_txd <= 8'h06;
                    8'd10:
                        gmii_txd <= ip_checksum[15:8];
                    8'd11:
                        gmii_txd <= ip_checksum[7:0];
                    8'd12:
                        gmii_txd <= LOCAL_IP[31:24];
                    8'd13:
                        gmii_txd <= LOCAL_IP[23:16];
                    8'd14:
                        gmii_txd <= LOCAL_IP[15:8];
                    8'd15:
                        gmii_txd <= LOCAL_IP[7:0];
                    8'd16:
                        gmii_txd <= remote_ip_latched[31:24];
                    8'd17:
                        gmii_txd <= remote_ip_latched[23:16];
                    8'd18:
                        gmii_txd <= remote_ip_latched[15:8];
                    default:
                        gmii_txd <= remote_ip_latched[7:0];
                endcase
                if (byte_count == 8'd19) begin
                    byte_count <= 8'd0;
                    state      <= ST_TCP;
                end
                else begin
                    byte_count <= byte_count + 1'b1;
                end
            end

            ST_TCP: begin
                gmii_tx_en <= 1'b1;
                crc_en     <= 1'b1;
                case (byte_count)
                    8'd0:
                        gmii_txd <= LOCAL_PORT[15:8];
                    8'd1:
                        gmii_txd <= LOCAL_PORT[7:0];
                    8'd2:
                        gmii_txd <= remote_port_latched[15:8];
                    8'd3:
                        gmii_txd <= remote_port_latched[7:0];
                    8'd4:
                        gmii_txd <= seq_latched[31:24];
                    8'd5:
                        gmii_txd <= seq_latched[23:16];
                    8'd6:
                        gmii_txd <= seq_latched[15:8];
                    8'd7:
                        gmii_txd <= seq_latched[7:0];
                    8'd8:
                        gmii_txd <= ack_latched[31:24];
                    8'd9:
                        gmii_txd <= ack_latched[23:16];
                    8'd10:
                        gmii_txd <= ack_latched[15:8];
                    8'd11:
                        gmii_txd <= ack_latched[7:0];
                    8'd12:
                        gmii_txd <= 8'h50;
                    8'd13:
                        gmii_txd <= flags_latched;
                    8'd14:
                        gmii_txd <= window_latched[15:8];
                    8'd15:
                        gmii_txd <= window_latched[7:0];
                    8'd16:
                        gmii_txd <= tcp_checksum[15:8];
                    8'd17:
                        gmii_txd <= tcp_checksum[7:0];
                    default:
                        gmii_txd <= 8'h00;
                endcase

                // Prefetch the synchronous RAM so byte zero is ready when
                // ST_PAYLOAD begins.
                if ((byte_count == 8'd17) && (payload_length_latched != 16'd0))
                    payload_rd_addr <= payload_start_latched;
                if ((byte_count == 8'd19) && (payload_length_latched != 16'd0))
                    payload_rd_addr <= payload_start_latched + 1'b1;

                if (byte_count == 8'd19) begin
                    byte_count    <= 8'd0;
                    payload_count <= 16'd0;
                    if (payload_length_latched != 16'd0)
                        state <= ST_PAYLOAD;
                    else if (pad_length != 8'd0)
                        state <= ST_PAD;
                    else
                        state <= ST_FCS;
                end
                else begin
                    byte_count <= byte_count + 1'b1;
                end
            end

            ST_PAYLOAD: begin
                gmii_tx_en <= 1'b1;
                crc_en     <= 1'b1;
                gmii_txd   <= payload_rd_data;
                payload_rd_addr <= payload_start_latched + payload_count + 2'd2;
                if (payload_count == (payload_length_latched - 1'b1)) begin
                    payload_count <= 16'd0;
                    byte_count    <= 8'd0;
                    if (pad_length != 8'd0)
                        state <= ST_PAD;
                    else
                        state <= ST_FCS;
                end
                else begin
                    payload_count <= payload_count + 1'b1;
                end
            end

            ST_PAD: begin
                gmii_tx_en <= 1'b1;
                crc_en     <= 1'b1;
                gmii_txd   <= 8'h00;
                if (byte_count == (pad_length - 1'b1)) begin
                    byte_count <= 8'd0;
                    state      <= ST_FCS;
                end
                else begin
                    byte_count <= byte_count + 1'b1;
                end
            end
            //456
            ST_FCS: begin
                gmii_tx_en <= 1'b1;
                crc_en     <= 1'b0;
                case (byte_count)
                    8'd0:
                        gmii_txd <= {~crc_next[24],  ~crc_next[25],
                                     ~crc_next[26],  ~crc_next[27],
                                     ~crc_next[28],  ~crc_next[29],
                                     ~crc_next[30],  ~crc_next[31]};
                    8'd1:
                        gmii_txd <= {~crc_data[16], ~crc_data[17],
                                     ~crc_data[18], ~crc_data[19],
                                     ~crc_data[20], ~crc_data[21],
                                     ~crc_data[22], ~crc_data[23]};
                    8'd2:
                        gmii_txd <= {~crc_data[8],  ~crc_data[9],
                                     ~crc_data[10], ~crc_data[11],
                                     ~crc_data[12], ~crc_data[13],
                                     ~crc_data[14], ~crc_data[15]};
                    default:
                        gmii_txd <= {~crc_data[0], ~crc_data[1],
                                     ~crc_data[2], ~crc_data[3],
                                     ~crc_data[4], ~crc_data[5],
                                     ~crc_data[6], ~crc_data[7]};
                endcase
                if (byte_count == 8'd3) begin
                    byte_count <= 8'd0;
                    ifg_count  <= 5'd0;
                    state      <= ST_IFG;
                    crc_clr    <= 1'b1;
                end
                else begin
                    byte_count <= byte_count + 1'b1;
                end
            end

            ST_IFG: begin
                gmii_tx_en <= 1'b0;
                gmii_txd   <= 8'd0;
                crc_en     <= 1'b0;
                if (ifg_count == 5'd11) begin
                    ifg_count <= 5'd0;
                    busy      <= 1'b0;
                    tx_done   <= 1'b1;
                    state     <= ST_IDLE;
                end
                else begin
                    ifg_count <= ifg_count + 1'b1;
                end
            end

            default:
                state <= ST_IDLE;
        endcase
    end
end

endmodule
