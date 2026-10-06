`timescale 1ns / 1ps

module phy_ctrl #(
    parameter [4:0] PHY_ADDR = 5'h04,
    parameter integer MDC_DIVIDE = 20,
    parameter integer RESET_CYCLES = 1_000_000
)(
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    output wire       eth_rst_n,
    output wire       eth_mdc,
    inout  wire       eth_mdio,
    output wire       phy_ready,
    output wire       phy_link_up,
    output wire       phy_autoneg_done,
    output wire [1:0] phy_link_speed
);

wire        mdio_input;
wire        mdio_output;
wire        mdio_output_enable;
wire        mdio_done;
wire [15:0] mdio_read_data;
wire        mdio_read_ack;
wire        mdio_busy;
wire        mdio_execute;
wire        mdio_read_not_write;
wire [4:0]  mdio_register;
wire [15:0] mdio_write_data;

phy_reset_ctrl #(
    .RESET_CYCLES(RESET_CYCLES)
) u_reset (
    .clk       (sys_clk),
    .sys_rst_n (sys_rst_n),
    .phy_rst_n (eth_rst_n),
    .phy_ready (phy_ready)
);

IOBUF u_mdio_pin (
    .I  (mdio_output),
    .T  (~mdio_output_enable),
    .O  (mdio_input),
    .IO (eth_mdio)
);

mdio_dri #(
    .PHY_ADDR   (PHY_ADDR),
    .MDC_DIVIDE (MDC_DIVIDE)
) u_mdio (
    .clk        (sys_clk),
    .rst_n      (phy_ready),
    .op_exec    (mdio_execute),
    .op_rh_wl   (mdio_read_not_write),
    .op_addr    (mdio_register),
    .op_wr_data (mdio_write_data),
    .op_done    (mdio_done),
    .op_rd_data (mdio_read_data),
    .op_rd_ack  (mdio_read_ack),
    .busy       (mdio_busy),
    .eth_mdc    (eth_mdc),
    .mdio_i     (mdio_input),
    .mdio_o     (mdio_output),
    .mdio_oe    (mdio_output_enable)
);

phy_mdio_ctrl u_status_poll (
    .clk          (sys_clk),
    .rst_n        (phy_ready),
    .op_done      (mdio_done),
    .op_rd_data   (mdio_read_data),
    .op_rd_ack    (mdio_read_ack),
    .op_exec      (mdio_execute),
    .op_rh_wl     (mdio_read_not_write),
    .op_addr      (mdio_register),
    .op_wr_data   (mdio_write_data),
    .link_up      (phy_link_up),
    .autoneg_done (phy_autoneg_done),
    .link_speed   (phy_link_speed)
);

wire unused_busy = mdio_busy;

endmodule

