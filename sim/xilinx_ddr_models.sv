`timescale 1ns / 1ps

// Minimal behavioural models used only by the portable Icarus testbench.
// Vivado synthesis and simulation must use the UNISIM primitives instead.
module BUFG(input wire I, output wire O);
assign O = I;
endmodule

module BUFIO(input wire I, output wire O);
assign O = I;
endmodule

module IOBUF(
    input  wire I,
    input  wire T,
    output wire O,
    inout  wire IO
);
assign IO = T ? 1'bz : I;
assign O  = IO;
endmodule

module ODDR #(
    parameter DDR_CLK_EDGE = "SAME_EDGE",
    parameter INIT = 1'b0,
    parameter SRTYPE = "SYNC"
)(
    output reg Q,
    input wire C,
    input wire CE,
    input wire D1,
    input wire D2,
    input wire R,
    input wire S
);
initial Q = INIT;
always @(posedge C) begin
    if (R) Q <= 1'b0;
    else if (S) Q <= 1'b1;
    else if (CE) Q <= D1;
end
always @(negedge C) begin
    if (R) Q <= 1'b0;
    else if (S) Q <= 1'b1;
    else if (CE) Q <= D2;
end
endmodule

module IDDR #(
    parameter DDR_CLK_EDGE = "SAME_EDGE_PIPELINED",
    parameter INIT_Q1 = 1'b0,
    parameter INIT_Q2 = 1'b0,
    parameter SRTYPE = "SYNC"
)(
    output reg Q1,
    output reg Q2,
    input wire C,
    input wire CE,
    input wire D,
    input wire R,
    input wire S
);
reg rising_sample;
reg falling_sample;
initial begin
    Q1 = INIT_Q1;
    Q2 = INIT_Q2;
    rising_sample = INIT_Q1;
    falling_sample = INIT_Q2;
end
always @(negedge C) begin
    if (CE)
        falling_sample <= D;
end
always @(posedge C) begin
    if (R) begin
        Q1 <= 1'b0;
        Q2 <= 1'b0;
    end else if (S) begin
        Q1 <= 1'b1;
        Q2 <= 1'b1;
    end else if (CE) begin
        Q1 <= rising_sample;
        Q2 <= falling_sample;
        rising_sample <= D;
    end
end
endmodule
