`timescale 1ns / 1ps

module phy_reset_ctrl #(
    parameter integer RESET_CYCLES = 1_000_000
)(
    input  wire clk,
    input  wire sys_rst_n,
    output reg  phy_rst_n,
    output reg  phy_ready
);

reg [31:0] elapsed_cycles;

always @(posedge clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        elapsed_cycles <= 32'd0;
        phy_rst_n      <= 1'b0;
        phy_ready      <= 1'b0;
    end else if (!phy_ready) begin
        if ((RESET_CYCLES == 0) || (elapsed_cycles >= RESET_CYCLES - 1)) begin
            phy_rst_n <= 1'b1;
            phy_ready <= 1'b1;
        end else begin
            elapsed_cycles <= elapsed_cycles + 1'b1;
            phy_rst_n      <= 1'b0;
        end
    end
end

endmodule

