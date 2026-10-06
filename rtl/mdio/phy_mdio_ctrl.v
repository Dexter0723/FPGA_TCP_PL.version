`timescale 1ns / 1ps

// Periodically reads the standard Basic Mode Status Register and the
// YT8511/YT8531 PHY-specific status register.
module phy_mdio_ctrl #(
    parameter integer STARTUP_DELAY = 250_000,
    parameter integer POLL_DELAY    = 250_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        op_done,
    input  wire [15:0] op_rd_data,
    input  wire        op_rd_ack,
    output reg         op_exec,
    output wire        op_rh_wl,
    output reg  [4:0]  op_addr,
    output wire [15:0] op_wr_data,
    output reg         link_up,
    output reg         autoneg_done,
    output reg  [1:0]  link_speed
);

localparam [3:0] WAIT_STARTUP   = 4'd0;
localparam [3:0] ISSUE_BMSR_1   = 4'd1;
localparam [3:0] WAIT_BMSR_1    = 4'd2;
localparam [3:0] ISSUE_BMSR_2   = 4'd3;
localparam [3:0] WAIT_BMSR_2    = 4'd4;
localparam [3:0] ISSUE_PHY_STAT = 4'd5;
localparam [3:0] WAIT_PHY_STAT  = 4'd6;
localparam [3:0] WAIT_NEXT_POLL = 4'd7;

reg [3:0] state;
reg [31:0] delay_counter;

assign op_rh_wl   = 1'b1;
assign op_wr_data = 16'd0;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state         <= WAIT_STARTUP;
        delay_counter <= 32'd0;
        op_exec       <= 1'b0;
        op_addr       <= 5'h01;
        link_up       <= 1'b0;
        autoneg_done  <= 1'b0;
        link_speed    <= 2'b00;
    end else begin
        op_exec <= 1'b0;

        case (state)
            WAIT_STARTUP: begin
                if ((STARTUP_DELAY == 0) || (delay_counter >= STARTUP_DELAY - 1)) begin
                    delay_counter <= 32'd0;
                    state <= ISSUE_BMSR_1;
                end else begin
                    delay_counter <= delay_counter + 1'b1;
                end
            end

            ISSUE_BMSR_1: begin
                op_addr <= 5'h01;
                op_exec <= 1'b1;
                state   <= WAIT_BMSR_1;
            end

            WAIT_BMSR_1: begin
                if (op_done)
                    state <= ISSUE_BMSR_2;
            end

            ISSUE_BMSR_2: begin
                op_addr <= 5'h01;
                op_exec <= 1'b1;
                state   <= WAIT_BMSR_2;
            end

            WAIT_BMSR_2: begin
                if (op_done) begin
                    if (!op_rd_ack) begin
                        link_up      <= op_rd_data[2];
                        autoneg_done <= op_rd_data[5];
                    end else begin
                        link_up      <= 1'b0;
                        autoneg_done <= 1'b0;
                    end
                    state <= ISSUE_PHY_STAT;
                end
            end

            ISSUE_PHY_STAT: begin
                op_addr <= 5'h11;
                op_exec <= 1'b1;
                state   <= WAIT_PHY_STAT;
            end

            WAIT_PHY_STAT: begin
                if (op_done) begin
                    if (!op_rd_ack)
                        link_speed <= op_rd_data[15:14];
                    else
                        link_speed <= 2'b00;
                    delay_counter <= 32'd0;
                    state <= WAIT_NEXT_POLL;
                end
            end

            WAIT_NEXT_POLL: begin
                if ((POLL_DELAY == 0) || (delay_counter >= POLL_DELAY - 1)) begin
                    delay_counter <= 32'd0;
                    state <= ISSUE_BMSR_1;
                end else begin
                    delay_counter <= delay_counter + 1'b1;
                end
            end

            default: state <= WAIT_STARTUP;
        endcase
    end
end

endmodule

