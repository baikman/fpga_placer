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
    
    localparam WAITING_START = 3'd0;
    localparam WAITING_CELL = 3'd1;
    localparam WAITING_NET = 3'd2;
    localparam WAITING_LOAD_COUNT = 3'd3;
    localparam WAITING_DRIVER = 3'd4;
    localparam WAITING_LOAD = 3'd5;
    localparam NEXT_NET = 3'd6;

    reg [2:0] state;
    reg [7:0] net_load_count [0:254];
    reg [7:0] net_index;
    reg [7:0] net_driver [0:254];
    reg [7:0] loads_remaining;
    reg [7:0] load_cell [0:254];
    reg [7:0] load_ptr;
    reg [7:0] net_load_start [0:254];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= WAITING_START;
            net_index <= 8'd0;
            cell_count <= 8'd0;
            net_count <= 8'd0;
            load_ptr <= 8'd0;
            loads_remaining <= 8'd0;
            done <= 1'b0;
        end else begin
            case (state)

                WAITING_START: begin
                    if (start) begin
                        net_index <= 8'd0;
                        load_ptr <= 8'd0;
                        loads_remaining <= 8'd0;
                        done <= 1'b0;
                        state <= WAITING_CELL;
                    end
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
                        state <= WAITING_LOAD_COUNT;
                    end
                end

                WAITING_LOAD_COUNT: begin
                    if (rx_valid) begin
                        net_load_count[net_index] <= rx_data;
                        net_load_start[net_index] <= load_ptr;
                        loads_remaining <= rx_data;
                        state <= WAITING_DRIVER;
                    end
                end

                WAITING_DRIVER: begin
                    if (rx_valid) begin
                        net_driver[net_index] <= rx_data;
                        if (loads_remaining == 0)
                            state <= NEXT_NET;
                        else
                            state <= WAITING_LOAD;
                    end
                end

                WAITING_LOAD: begin
                    if (rx_valid) begin
                        load_cell[load_ptr] <= rx_data;
                        load_ptr <= load_ptr + 8'd1;
                        loads_remaining <= loads_remaining - 8'd1;

                        if (loads_remaining == 8'd1)
                            state <= NEXT_NET;
                    end
                end

                NEXT_NET: begin
                    if (net_index == net_count - 8'd1) begin
                        done <= 1'b1;
                        state <= WAITING_START;
                    end else begin
                        net_index <= net_index + 8'd1;
                        state <= WAITING_LOAD_COUNT;
                    end
                end

                default: begin
                    state <= WAITING_START;
                end
            endcase
        end
    end

endmodule