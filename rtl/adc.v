`timescale 1ns / 1ps

module adc (
           input  wire       sys_clk,
           input  wire       sys_rst_n,

           input  wire       capture_enable,
           input  wire [7:0] ad_data,

           input  wire       ad_tready,
           output reg  [7:0] ad_tdata,
           output reg        ad_tvalid,
           output wire       ad_tlast,

           output wire       adc_clk,
           output reg        ad_overflow,
           output wire       fifo_reset_n
       );

reg adc_clk_div;

//25 MHz
always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
        adc_clk_div <= 1'b0;
    else
        adc_clk_div <= ~adc_clk_div;
end

assign adc_clk = adc_clk_div;
assign ad_tlast = 1'b0;

reg capture_meta;
reg capture_sync;

always @(posedge adc_clk_div or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        capture_meta <= 1'b0;
        capture_sync <= 1'b0;
    end
    else begin
        capture_meta <= capture_enable;
        capture_sync <= capture_meta;
    end
end

assign fifo_reset_n = sys_rst_n && capture_sync;

// ADC → AXI-Stream
always @(posedge adc_clk_div or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        ad_tdata    <= 8'd0;
        ad_tvalid   <= 1'b0;
        ad_overflow <= 1'b0;
    end
    else if (!capture_sync) begin
        ad_tvalid <= 1'b0;
        ad_overflow <= 1'b0;
    end
    else begin
        if (!ad_tvalid || ad_tready) begin
            ad_tdata  <= ad_data;
            ad_tvalid <= 1'b1;
        end
        else begin
            ad_overflow <= 1'b1;
        end
    end
end

endmodule
