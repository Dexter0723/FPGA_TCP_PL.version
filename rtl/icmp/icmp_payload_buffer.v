`timescale 1ns / 1ps

// One-packet byte FIFO used by the ICMP echo path.  In this design the RX and
// TX GMII clocks are the same clock (the recovered RGMII RX clock).
module icmp_payload_buffer (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       wr_en,
    input  wire [7:0] wr_data,
    input  wire       rd_en,
    output wire [7:0] rd_data
);

(* ram_style = "distributed" *) reg [7:0] memory [0:2047];
reg [10:0] write_pointer;
reg [10:0] read_pointer;

assign rd_data = memory[read_pointer];

always @(posedge clk) begin
    if (!rst_n) begin
        write_pointer <= 11'd0;
        read_pointer  <= 11'd0;
    end else begin
        if (wr_en) begin
            memory[write_pointer] <= wr_data;
            write_pointer <= write_pointer + 1'b1;
        end
        if (rd_en)
            read_pointer <= read_pointer + 1'b1;
    end
end

endmodule
