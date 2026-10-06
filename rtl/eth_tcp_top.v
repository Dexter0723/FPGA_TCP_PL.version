`timescale 1ns / 1ps

// Navigator ZYNQ pure-PL 1 GbE TCP demonstration top level.
// A PC connects to 192.168.1.10:5000. Once established, the PL continuously
// transmits an incrementing byte pattern through the hardware TCP engine.
module eth_tcp_top #(
           parameter [47:0] BOARD_MAC = 48'h00_11_22_33_44_55,
           parameter [31:0] BOARD_IP  = {8'd192, 8'd168, 8'd1, 8'd10},
           parameter [15:0] TCP_PORT  = 16'd5000
       )(
           input wire       core_async_rst_n,

           output wire       tcp_app_clk,
           output wire       tcp_connected_o,

           // FPGA -> PC
           input  wire [7:0] app_tx_data,
           input  wire       app_tx_valid,
           input  wire       app_tx_flush,
           output wire       app_tx_ready,

           // PC -> FPGA
           output wire [7:0] app_rx_data,
           output wire       app_rx_valid,
           output wire       app_rx_last,
           input  wire       app_rx_ready,

           input  wire       gmii_rx_clk,
           input  wire       gmii_rx_dv,
           input  wire [7:0] gmii_rxd,

           input  wire       gmii_tx_clk,
           output wire       gmii_tx_en,
           output wire [7:0] gmii_txd
       );

reg  [3:0] gmii_reset_pipe;
wire       gmii_rst_n = gmii_reset_pipe[3];

//ICMP
wire        icmp_rec_pkt_done;
reg         icmp_tx_start;
wire        icmp_tx_done;
wire        icmp_gmii_tx_en;
wire [7:0]  icmp_gmii_txd;
reg         icmp_pending;

//ARP
wire       arp_gmii_tx_en;
wire [7:0] arp_gmii_txd;
wire       arp_rx_done;
wire       arp_rx_type;
wire [47:0] arp_src_mac;
wire [31:0] arp_src_ip;
reg        arp_tx_en;
wire       arp_tx_done;
reg        arp_pending;

//TCP
wire       tcp_tx_request;
reg        tcp_tx_grant;
wire       tcp_gmii_tx_en;
wire [7:0] tcp_gmii_txd;
wire       tcp_tx_busy;
wire       tcp_tx_done;
wire       tcp_connected;

reg  [1:0] tx_owner;
localparam [1:0] OWNER_IDLE = 2'd0;
localparam [1:0] OWNER_ARP  = 2'd1;
localparam [1:0] OWNER_ICMP = 2'd2;
localparam [1:0] OWNER_TCP  = 2'd3;

// assign eth_rst_n = phy_rst_n;
// assign gmii_tx_en = (tx_owner == OWNER_ARP) ? arp_gmii_tx_en :
//        (tx_owner == OWNER_TCP) ? tcp_gmii_tx_en : 1'b0;
// assign gmii_txd   = (tx_owner == OWNER_ARP) ? arp_gmii_txd :
//        (tx_owner == OWNER_TCP) ? tcp_gmii_txd : 8'd0;
assign gmii_tx_en =
       (tx_owner == OWNER_ARP)  ? arp_gmii_tx_en  :
       (tx_owner == OWNER_ICMP) ? icmp_gmii_tx_en :
       (tx_owner == OWNER_TCP)  ? tcp_gmii_tx_en  :
       1'b0;

assign gmii_txd =
       (tx_owner == OWNER_ARP)  ? arp_gmii_txd  :
       (tx_owner == OWNER_ICMP) ? icmp_gmii_txd :
       (tx_owner == OWNER_TCP)  ? tcp_gmii_txd  :
       8'd0;

assign tcp_app_clk     = gmii_rx_clk;
assign tcp_connected_o = tcp_connected;

always @(posedge gmii_rx_clk or negedge core_async_rst_n) begin
    if (!core_async_rst_n)
        gmii_reset_pipe <= 4'b0000;
    else
        gmii_reset_pipe <= {gmii_reset_pipe[2:0], 1'b1};
end

// Packet-granular transmitter ownership. A selected producer retains the
// GMII output through FCS and IFG, preventing the old mid-frame ARP switch.
always @(posedge gmii_rx_clk or negedge gmii_rst_n) begin
    if (!gmii_rst_n) begin
        tx_owner     <= OWNER_IDLE;
        arp_pending  <= 1'b0;
        arp_tx_en    <= 1'b0;

        icmp_pending  <= 1'b0;
        icmp_tx_start <= 1'b0;

        tcp_tx_grant <= 1'b0;
    end
    else begin
        arp_tx_en     <= 1'b0;
        icmp_tx_start <= 1'b0;
        tcp_tx_grant  <= 1'b0;

        if (arp_rx_done && !arp_rx_type)
            arp_pending <= 1'b1;

        if (icmp_rec_pkt_done)
            icmp_pending <= 1'b1;


        case (tx_owner)
            OWNER_IDLE: begin
                if (arp_pending) begin
                    arp_tx_en   <= 1'b1;
                    arp_pending <= 1'b0;
                    tx_owner    <= OWNER_ARP;
                end
                else if (icmp_pending) begin
                    icmp_tx_start <= 1'b1;
                    icmp_pending  <= 1'b0;
                    tx_owner      <= OWNER_ICMP;
                end
                else if (tcp_tx_request) begin
                    tcp_tx_grant <= 1'b1;
                    tx_owner     <= OWNER_TCP;
                end
            end

            OWNER_ARP: begin
                if (arp_tx_done)
                    tx_owner <= OWNER_IDLE;
            end

            OWNER_ICMP: begin
                if (icmp_tx_done)
                    tx_owner <= OWNER_IDLE;
            end

            OWNER_TCP: begin
                if (tcp_tx_done)
                    tx_owner <= OWNER_IDLE;
            end
            default:
                tx_owner <= OWNER_IDLE;
        endcase
    end
end

icmp #(
         .BOARD_MAC (BOARD_MAC),
         .BOARD_IP  (BOARD_IP)
     ) u_icmp (
         .rst_n          (gmii_rst_n),

         .gmii_rx_clk    (gmii_rx_clk),
         .gmii_rx_dv     (gmii_rx_dv),
         .gmii_rxd       (gmii_rxd),

         .gmii_tx_clk    (gmii_tx_clk),
         .gmii_tx_en     (icmp_gmii_tx_en),
         .gmii_txd       (icmp_gmii_txd),

         .rec_pkt_done   (icmp_rec_pkt_done),

         .tx_start_en    (icmp_tx_start),
         .tx_done        (icmp_tx_done),

         .des_mac        (arp_src_mac),
         .des_ip         (arp_src_ip)
     );

arp #(
        .BOARD_MAC (BOARD_MAC),
        .BOARD_IP  (BOARD_IP),
        .DES_MAC   (48'hff_ff_ff_ff_ff_ff),
        .DES_IP    ({8'd192, 8'd168, 8'd1, 8'd102})
    ) u_arp (
        .rst_n       (gmii_rst_n),
        .gmii_rx_clk (gmii_rx_clk),
        .gmii_rx_dv  (gmii_rx_dv),
        .gmii_rxd    (gmii_rxd),
        .gmii_tx_clk (gmii_tx_clk),
        .gmii_tx_en  (arp_gmii_tx_en),
        .gmii_txd    (arp_gmii_txd),
        .arp_rx_done (arp_rx_done),
        .arp_rx_type (arp_rx_type),
        .src_mac     (arp_src_mac),
        .src_ip      (arp_src_ip),
        .arp_tx_en   (arp_tx_en),
        .arp_tx_type (1'b1),
        .des_mac     (arp_src_mac),
        .des_ip      (arp_src_ip),
        .tx_done     (arp_tx_done)
    );

tcp_engine #(
               .LOCAL_MAC  (BOARD_MAC),
               .LOCAL_IP   (BOARD_IP),
               .LOCAL_PORT (TCP_PORT)
           ) u_tcp_engine (
               .clk            (gmii_rx_clk),
               .rst_n          (gmii_rst_n),
               .gmii_rx_dv     (gmii_rx_dv),
               .gmii_rxd       (gmii_rxd),

               // FPGA -> PC
               .app_tx_valid   (app_tx_valid),
               .app_tx_data    (app_tx_data),
               .app_tx_flush   (app_tx_flush),
               .app_tx_ready   (app_tx_ready),

               // PC -> FPGA
               .app_rx_data    (app_rx_data),
               .app_rx_valid   (app_rx_valid),
               .app_rx_last    (app_rx_last),
               .app_rx_ready   (app_rx_ready),

               .tx_request     (tcp_tx_request),
               .tx_grant       (tcp_tx_grant),
               .gmii_tx_en     (tcp_gmii_tx_en),
               .gmii_txd       (tcp_gmii_txd),
               .tx_busy        (tcp_tx_busy),
               .tx_done        (tcp_tx_done),
               .connected      (tcp_connected)
           );

endmodule
