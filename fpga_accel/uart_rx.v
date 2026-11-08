`default_nettype none

module uart_rx #(
    parameter integer CLKS_PER_BIT = 868
) (
    input wire clk,
    input wire rst,
    input wire rx,
    output reg [7:0] data,
    output reg valid
);

    localparam IDLE = 2'd0;
    localparam START = 2'd1;
    localparam DATA = 2'd2;
    localparam STOP = 2'd3;

    reg rx_meta;
    reg rx_sync;
    reg [1:0] state;
    reg [15:0] clk_count;
    reg [2:0] bit_idx;
    reg [7:0] data_bits;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
            state <= IDLE;
            clk_count <= 16'd0;
            bit_idx <= 3'd0;
            data_bits <= 8'd0;
            data <= 8'd0;
            valid <= 1'b0;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
            valid <= 1'b0;

            case (state)
                IDLE: begin
                    if (!rx_sync) begin
                        clk_count <= 16'd0;
                        state <= START;
                    end
                end
                START: begin
                    if (clk_count == (CLKS_PER_BIT / 2) - 1) begin
                        clk_count <= 16'd0;
                        if (!rx_sync) begin
                            bit_idx <= 3'd0;
                            state <= DATA;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end
                DATA: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'd0;
                        data_bits[bit_idx] <= rx_sync;
                        if (bit_idx == 3'd7)
                            state <= STOP;
                        else
                            bit_idx <= bit_idx + 1'b1;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end
                STOP: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'd0;
                        state <= IDLE;
                        if (rx_sync) begin
                            data <= data_bits;
                            valid <= 1'b1;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
