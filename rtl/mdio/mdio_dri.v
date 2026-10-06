`timescale 1ns / 1ps

// IEEE 802.3 Clause 22 MDIO controller.
// op_rh_wl = 1 performs a read; op_rh_wl = 0 performs a write.
module mdio_dri #(
    parameter [4:0] PHY_ADDR = 5'h04,
    parameter integer MDC_DIVIDE = 20
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        op_exec,
    input  wire        op_rh_wl,
    input  wire [4:0]  op_addr,
    input  wire [15:0] op_wr_data,
    output reg         op_done,
    output reg  [15:0] op_rd_data,
    output reg         op_rd_ack,
    output reg         busy,
    output reg         eth_mdc,
    input  wire        mdio_i,
    output reg         mdio_o,
    output reg         mdio_oe
);

localparam integer HALF_PERIOD = (MDC_DIVIDE < 2) ? 1 : (MDC_DIVIDE / 2);

reg [15:0] divider_count;
reg [5:0]  bit_index;
reg        read_operation;
reg [4:0]  register_address;
reg [15:0] write_value;

always @(*) begin
    mdio_o  = 1'b1;
    mdio_oe = 1'b0;

    if (busy) begin
        // The station releases both turnaround bits and all data bits on read.
        mdio_oe = !(read_operation && (bit_index >= 46));

        if (bit_index < 32) begin
            mdio_o = 1'b1;
        end else begin
            case (bit_index)
                32: mdio_o = 1'b0;                  // ST = 01
                33: mdio_o = 1'b1;
                34: mdio_o = read_operation;        // OP = 10 read, 01 write
                35: mdio_o = ~read_operation;
                36: mdio_o = PHY_ADDR[4];
                37: mdio_o = PHY_ADDR[3];
                38: mdio_o = PHY_ADDR[2];
                39: mdio_o = PHY_ADDR[1];
                40: mdio_o = PHY_ADDR[0];
                41: mdio_o = register_address[4];
                42: mdio_o = register_address[3];
                43: mdio_o = register_address[2];
                44: mdio_o = register_address[1];
                45: mdio_o = register_address[0];
                46: mdio_o = 1'b1;                  // Write turnaround = 10
                47: mdio_o = 1'b0;
                default: mdio_o = write_value[63 - bit_index];
            endcase
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        divider_count   <= 16'd0;
        bit_index       <= 6'd0;
        read_operation  <= 1'b0;
        register_address <= 5'd0;
        write_value     <= 16'd0;
        op_done         <= 1'b0;
        op_rd_data      <= 16'd0;
        op_rd_ack       <= 1'b1;
        busy            <= 1'b0;
        eth_mdc         <= 1'b0;
    end else begin
        op_done <= 1'b0;

        if (!busy) begin
            eth_mdc       <= 1'b0;
            divider_count <= 16'd0;
            bit_index     <= 6'd0;

            if (op_exec) begin
                busy             <= 1'b1;
                read_operation   <= op_rh_wl;
                register_address <= op_addr;
                write_value      <= op_wr_data;
                op_rd_data       <= 16'd0;
                op_rd_ack        <= 1'b1;
            end
        end else if (divider_count == HALF_PERIOD - 1) begin
            divider_count <= 16'd0;

            if (!eth_mdc) begin
                // Read MDIO at the rising MDC edge.
                eth_mdc <= 1'b1;
                if (read_operation && (bit_index == 47))
                    op_rd_ack <= mdio_i;
                if (read_operation && (bit_index >= 48))
                    op_rd_data[63 - bit_index] <= mdio_i;
            end else begin
                // Advance only after the falling edge, keeping output data
                // stable around the complete high half-cycle.
                eth_mdc <= 1'b0;
                if (bit_index == 63) begin
                    busy    <= 1'b0;
                    op_done <= 1'b1;
                end else begin
                    bit_index <= bit_index + 1'b1;
                end
            end
        end else begin
            divider_count <= divider_count + 1'b1;
        end
    end
end

endmodule

