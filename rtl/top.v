`timescale 1ns / 1ps

module top (
           input  wire sys_clk,
           input  wire sys_rst_n,

           //ADC
           input [7:0] ad_data,
           input ad_otr,

           output adc_clk,

           //Ethernet
           input  wire eth_rxc,
           input  wire eth_rx_ctl,
           input  wire [3:0] eth_rxd,

           output wire eth_txc,
           output wire eth_tx_ctl,
           output wire [3:0] eth_txd,

           output wire eth_rst_n,
           output wire eth_mdc,
           inout  wire eth_mdio
       );

//phy mdio
wire       phy_ready;
wire       phy_link_up;
wire       phy_autoneg_done;
wire [1:0] phy_link_speed;

wire       core_async_rst_n;

assign core_async_rst_n = sys_rst_n && phy_ready;

//TCP Port IP MAC
localparam [47:0] BOARD_MAC = 48'h00_11_22_33_44_55;
localparam [31:0] BOARD_IP  = {8'd192, 8'd168, 8'd1, 8'd10};
localparam [15:0] TCP_PORT  = 16'd5000;

wire       tcp_app_clk;
wire       tcp_connected;

wire [7:0] tcp_app_data;
wire       tcp_app_valid;
wire       tcp_app_flush;
wire       tcp_app_ready;
wire       tcp_tx_fire;

wire [7:0] tcp_rx_data;
wire       tcp_rx_valid;
wire       tcp_rx_last;
wire       tcp_rx_ready;
wire       tcp_rx_fire;

// reg        capture_enable;
reg        rx_packet_done;

assign tcp_rx_ready = 1'b1;
// assign tcp_rx_fire  = tcp_rx_valid && tcp_rx_ready;

wire       gmii_rx_clk;
wire       gmii_rx_dv;
wire [7:0] gmii_rxd;

wire       gmii_tx_clk;
wire       gmii_tx_en;
wire [7:0] gmii_txd;

// always @(posedge tcp_app_clk or negedge sys_rst_n) begin
//     if (!sys_rst_n) begin
//         capture_enable <= 1'b0;
//         rx_packet_done <= 1'b0;
//     end
//     else begin
//         rx_packet_done <= 1'b0;

//         if (tcp_rx_fire) begin
//             case (tcp_rx_data)
//                 8'h01:
//                     capture_enable <= 1'b1;

//                 8'h00:
//                     capture_enable <= 1'b0;

//                 default:
//                     capture_enable <= capture_enable;
//             endcase

//             if (tcp_rx_last)
//                 rx_packet_done <= 1'b1;
//         end
//     end
// end

//========================== test ==========================
// wire [7:0] sample_cnt;
// assign tcp_app_valid = tcp_connected;

// test_counter test_counter_inst (
//                  .sys_clk        (tcp_app_clk),
//                  .sys_rst_n      (sys_rst_n),

//                  .tcp_app_valid  (tcp_app_valid),
//                  .tcp_app_ready  (tcp_app_ready),

//                  .sample_cnt     (sample_cnt)
//              );
//==========================================================

//========================== ADC ==========================
wire [7:0] ad_tdata;
wire ad_tvalid;
wire ad_tlast;
wire ad_tready;

wire ad_overflow;
wire adc_fifo_reset_n;

adc adc_inst (
        .sys_clk        (sys_clk),
        .sys_rst_n      (sys_rst_n),

        .ad_data        (ad_data),
        .capture_enable (tcp_connected),

        .ad_tdata       (ad_tdata),
        .ad_tready      (ad_tready),
        .ad_tvalid      (ad_tvalid),
        .ad_tlast       (ad_tlast),

        .adc_clk        (adc_clk),
        .ad_overflow    (ad_overflow),
        .fifo_reset_n   (adc_fifo_reset_n)
    );

design_1 design_1_i(
             .s_axis_aclk_0     (adc_clk),
             .s_axis_aresetn_0  (adc_fifo_reset_n),

             .S_AXIS_0_tdata    (ad_tdata),
             .S_AXIS_0_tlast    (ad_tlast),
             .S_AXIS_0_tready   (ad_tready),
             .S_AXIS_0_tvalid   (ad_tvalid),

             .m_axis_aclk_0     (tcp_app_clk),
             .M_AXIS_0_tdata    (tcp_app_data),
             .M_AXIS_0_tlast    (tcp_app_flush),
             .M_AXIS_0_tready   (tcp_app_ready),
             .M_AXIS_0_tvalid   (tcp_app_valid)
         );
//==========================================================

phy_ctrl u_phy_ctrl (
             .sys_clk          (sys_clk),
             .sys_rst_n        (sys_rst_n),

             .eth_rst_n        (eth_rst_n),
             .eth_mdc          (eth_mdc),
             .eth_mdio         (eth_mdio),

             .phy_ready        (phy_ready),
             .phy_link_up      (phy_link_up),
             .phy_autoneg_done (phy_autoneg_done),
             .phy_link_speed   (phy_link_speed)
         );

eth_tcp_top #(
                .BOARD_MAC    (BOARD_MAC),
                .BOARD_IP     (BOARD_IP),
                .TCP_PORT     (TCP_PORT)
            ) tcp_inst (
                .core_async_rst_n   (core_async_rst_n),

                .tcp_app_clk        (tcp_app_clk),
                .tcp_connected_o    (tcp_connected),

                .app_tx_data        (tcp_app_data),
                .app_tx_valid       (tcp_app_valid),
                .app_tx_flush       (tcp_app_flush),
                .app_tx_ready       (tcp_app_ready),

                .app_rx_data        (tcp_rx_data),
                .app_rx_valid       (tcp_rx_valid),
                .app_rx_last        (tcp_rx_last),
                .app_rx_ready       (tcp_rx_ready),

                .gmii_rx_clk        (gmii_rx_clk),
                .gmii_rx_dv         (gmii_rx_dv),
                .gmii_rxd           (gmii_rxd),

                .gmii_tx_clk        (gmii_tx_clk),
                .gmii_tx_en         (gmii_tx_en),
                .gmii_txd           (gmii_txd)
            );

gmii_to_rgmii gmii_to_rgmii_inst (
                  .gmii_rx_clk  (gmii_rx_clk),
                  .gmii_rx_dv   (gmii_rx_dv),
                  .gmii_rxd     (gmii_rxd),

                  .gmii_tx_clk  (gmii_tx_clk),
                  .gmii_tx_en   (gmii_tx_en),
                  .gmii_txd     (gmii_txd),

                  .rgmii_rxc    (eth_rxc),
                  .rgmii_rx_ctl (eth_rx_ctl),
                  .rgmii_rxd    (eth_rxd),

                  .rgmii_txc    (eth_txc),
                  .rgmii_tx_ctl (eth_tx_ctl),
                  .rgmii_txd    (eth_txd)
              );

endmodule
