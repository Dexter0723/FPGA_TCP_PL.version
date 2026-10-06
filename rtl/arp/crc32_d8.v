`timescale 1ns / 1ps

// Reflected Ethernet CRC-32 accumulator for an 8-bit GMII stream.
// crc_data is the running (not complemented) register value.  Ethernet FCS
// bytes are ~crc_data[7:0], ~crc_data[15:8], ~crc_data[23:16], and
// ~crc_data[31:24], in that order.
module crc32_d8 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  data,
    input  wire        crc_en,
    input  wire        crc_clr,
    output reg  [31:0] crc_data,
    output wire [31:0] crc_next
);

function [31:0] update_byte;
    input [31:0] current;
    input [7:0]  octet;
    integer bit_number;
    reg [31:0] value;
    begin
        value = current;
        for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
            if (value[0] ^ octet[bit_number])
                value = (value >> 1) ^ 32'hEDB8_8320;
            else
                value = value >> 1;
        end
        update_byte = value;
    end
endfunction

assign crc_next = update_byte(crc_data, data);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        crc_data <= 32'hFFFF_FFFF;
    else if (crc_clr)
        crc_data <= 32'hFFFF_FFFF;
    else if (crc_en)
        crc_data <= crc_next;
end

endmodule

