`timescale 1ns / 1ps

// 64 KiB true dual-port byte RAM. Port A is written by the PL application,
// port B is read by the TCP frame transmitter. The registered read port is
// intentionally one cycle late so Vivado can infer block RAM.
module tcp_ram #(
           parameter ADDR_WIDTH = 16
       )(
           input  wire                  clk,
           input  wire                  wr_en,
           input  wire [ADDR_WIDTH-1:0] wr_addr,
           input  wire [7:0]            wr_data,
           input  wire [ADDR_WIDTH-1:0] rd_addr,
           output reg  [7:0]            rd_data
       );

(* ram_style = "block" *) reg [7:0] memory [0:(1 << ADDR_WIDTH)-1];

always @(posedge clk) begin
    if (wr_en)
        memory[wr_addr] <= wr_data;
    rd_data <= memory[rd_addr];
end

endmodule

