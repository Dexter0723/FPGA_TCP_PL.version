`timescale 1ns / 1ps

module tb_mdio_dri;

localparam [15:0] PHY_READ_DATA = 16'hA5C3;

reg clk = 1'b0;
reg rst_n = 1'b0;
reg op_exec = 1'b0;
reg op_rh_wl = 1'b1;
reg [4:0] op_addr = 5'd0;
reg [15:0] op_wr_data = 16'd0;
reg read_response = 1'b1;

wire op_done;
wire [15:0] op_rd_data;
wire op_rd_ack;
wire busy;
wire eth_mdc;
wire mdio_o;
wire mdio_oe;
wire mdio_i = read_response ?
              ((u_dut.bit_index == 47) ? 1'b0 :
               ((u_dut.bit_index >= 48) ?
                PHY_READ_DATA[63 - u_dut.bit_index] : 1'b1)) : 1'b1;

reg [63:0] driven_bits;
integer driven_count = 0;

always #10 clk = ~clk;

always @(posedge eth_mdc) begin
    if (!read_response && mdio_oe && (driven_count < 64)) begin
        driven_bits[63 - driven_count] <= mdio_o;
        driven_count <= driven_count + 1;
    end
end

mdio_dri #(
    .PHY_ADDR(5'h04),
    .MDC_DIVIDE(4)
) u_dut (
    .clk(clk),
    .rst_n(rst_n),
    .op_exec(op_exec),
    .op_rh_wl(op_rh_wl),
    .op_addr(op_addr),
    .op_wr_data(op_wr_data),
    .op_done(op_done),
    .op_rd_data(op_rd_data),
    .op_rd_ack(op_rd_ack),
    .busy(busy),
    .eth_mdc(eth_mdc),
    .mdio_i(mdio_i),
    .mdio_o(mdio_o),
    .mdio_oe(mdio_oe)
);

task start_operation;
    begin
        @(negedge clk);
        op_exec = 1'b1;
        @(negedge clk);
        op_exec = 1'b0;
    end
endtask

initial begin
    repeat (5) @(posedge clk);
    rst_n = 1'b1;

    op_rh_wl = 1'b1;
    op_addr = 5'h11;
    read_response = 1'b1;
    start_operation();
    wait (op_done);
    @(negedge clk);
    if (op_rd_ack !== 1'b0)
        $fatal(1, "PHY did not acknowledge Clause 22 read");
    if (op_rd_data !== PHY_READ_DATA)
        $fatal(1, "Read data mismatch: %04h", op_rd_data);
    if (mdio_oe !== 1'b0 || eth_mdc !== 1'b0)
        $fatal(1, "MDIO bus was not released cleanly");

    op_rh_wl = 1'b0;
    op_addr = 5'h03;
    op_wr_data = 16'hBEEF;
    read_response = 1'b0;
    driven_count = 0;
    driven_bits = 64'd0;
    start_operation();
    wait (op_done);
    @(negedge clk);

    if (driven_count != 64)
        $fatal(1, "Write transaction had %0d driven bits", driven_count);
    if (driven_bits[63:32] !== 32'hFFFF_FFFF ||
        driven_bits[31:30] !== 2'b01 ||
        driven_bits[29:28] !== 2'b01 ||
        driven_bits[27:23] !== 5'h04 ||
        driven_bits[22:18] !== 5'h03 ||
        driven_bits[17:16] !== 2'b10 ||
        driven_bits[15:0] !== 16'hBEEF)
        $fatal(1, "Clause 22 write frame is malformed: %016h", driven_bits);

    $display("PASS: Clause 22 MDIO read, write, turnaround, and bus release");
    $finish;
end

initial begin
    repeat (5000) @(posedge clk);
    $fatal(1, "MDIO simulation timeout");
end

endmodule

