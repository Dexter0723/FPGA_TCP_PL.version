`timescale 1ns / 1ps

module tb_crc32_d8;

reg clk = 1'b0;
reg rst_n = 1'b0;
reg [7:0] data = 8'd0;
reg crc_en = 1'b0;
reg crc_clr = 1'b0;
wire [31:0] crc_data;
wire [31:0] crc_next;

always #5 clk = ~clk;

crc32_d8 u_dut (
    .clk(clk), .rst_n(rst_n), .data(data),
    .crc_en(crc_en), .crc_clr(crc_clr),
    .crc_data(crc_data), .crc_next(crc_next)
);

task feed;
    input [7:0] value;
    begin
        @(negedge clk);
        data   = value;
        crc_en = 1'b1;
        @(posedge clk);
    end
endtask

initial begin
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    feed("1"); feed("2"); feed("3"); feed("4"); feed("5");
    feed("6"); feed("7"); feed("8"); feed("9");
    @(negedge clk);
    crc_en = 1'b0;
    #1;
    if (~crc_data !== 32'hCBF4_3926)
        $fatal(1, "CRC mismatch: got %08h", ~crc_data);
    $display("PASS: Ethernet CRC-32 reference vector");
    $finish;
end

endmodule

