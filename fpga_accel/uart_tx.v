`default_nettype none

module uart_tx #(
    parameter integer CLKS_PER_BIT = 868
) (
    input wire clk,
    input wire rst,

    input wire [7:0] data,
    input wire start,

    output reg tx,
    output reg busy
);

    localparam IDLE = 2'd0;
    localparam START = 2'd1;
    localparam DATA = 2'd2;
    localparam STOP = 2'd3;

    reg [1:0] state;

    reg [7:0] data_latched;

    reg [2:0] bit_idx;

    reg [15:0] clk_count;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            tx <= 1'b1;
            busy <= 1'b0;
            clk_count <= 15'b0;
            bit_idx <= 3'b0;
            data_latched <= 8'b0;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1'b1;
                    busy <= 1'b0;
                    clk_count <= 1'b0;
                    bit_idx <= 1'b0;
                    if (start) begin
                        data_latched <= data;
                        busy <= 1'b1;
                        state <= START;
                    end

                end 
                START: begin
                    tx <= 1'b0;
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'b0;
                        bit_idx <= 3'b0;
                        state <= DATA;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end
                DATA: begin
                    tx <= data_latched[bit_idx];
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'b0;
                        if (bit_idx == 3'd7) begin
                            state <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end
                STOP: begin
                    tx <= 1'b1;
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'b0;
                        state <= IDLE;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
