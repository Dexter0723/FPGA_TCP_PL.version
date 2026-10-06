`timescale 1ns / 1ps

module test_counter(
           input  wire sys_clk,
           input  wire sys_rst_n,

           input  wire tcp_app_valid,
           input wire tcp_app_ready,

           output reg [7:0] sample_cnt
       );

wire tcp_tx_fire;
assign tcp_tx_fire = tcp_app_valid && tcp_app_ready;

//TCP TX TEST
always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        sample_cnt <= 8'd0;
    end
    else if (!tcp_app_valid) begin
        sample_cnt <= 8'd0;
    end
    else if (tcp_tx_fire) begin
        sample_cnt <= sample_cnt + 8'd1;
    end
end

endmodule
