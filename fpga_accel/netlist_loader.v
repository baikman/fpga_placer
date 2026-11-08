`default_nettype  none

module netlist_loader (
    input wire clk,
    input wire rst,
    input wire start,
    input wire [7:0] rx_data,
    input wire rx_valid,

    output reg [7:0] cell_count,
    output reg [7:0] net_count,
    output reg done
);
    
    localparam WAITING_START = 2'd0,
    localparam WAITING_CELL = 2'd1;
    localparam WAITING_NET = 2'd2;
    localparam WAITING_BODY = 2'd3;

    reg [1:0] state;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= WAITING_START;
            cell_count <= 8'd0;
            net_count <= 8'd0;
            done <= 1'b0;
        end else begin
            case (state)
                WAITING_START: begin
                    if (start)
                        state <= WAITING_CELL;
                end

                WAITING_CELL: begin
                    if (rx_valid) begin
                        cell_count <= rx_data;
                        state <= WAITING_NET;
                    end
                end

                WAITING_NET: begin
                    if (rx_valid) begin
                        net_count <= rx_data;
                        state <= WAITING_BODY;
                    end
                end

                default: begin
                    state <= WAITING_START;
                end
            endcase
        end
    end

endmodule