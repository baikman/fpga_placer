`default_nettype  none

module netlist_loader (
    input wire clk,
    input wire rst,
    input wire start,
    input wire [7:0] rx_data,
    input wire rx_valid,

    input wire [7:0] read_net,
    input wire [7:0] read_load,
    output reg [7:0] read_driver,
    output reg [7:0] read_load_count,
    output reg [7:0] read_load_start,
    output reg [7:0] read_load_cell,

    input wire [7:0] read_net_1,
    input wire [7:0] read_load_1,
    output reg [7:0] read_driver_1,
    output reg [7:0] read_load_count_1,
    output reg [7:0] read_load_start_1,
    output reg [7:0] read_load_cell_1,

    output reg [7:0] cell_count,
    output reg [7:0] net_count,
    output reg [15:0] alpha,
    output reg done
);
    
    localparam WAITING_START = 4'd0;
    localparam WAITING_CELL = 4'd1;
    localparam WAITING_NET = 4'd2;
    localparam WAITING_LOAD_COUNT = 4'd3;
    localparam WAITING_DRIVER = 4'd4;
    localparam WAITING_LOAD = 4'd5;
    localparam NEXT_NET = 4'd6;
    localparam WAITING_ALPHA_LOW = 4'd7;
    localparam WAITING_ALPHA_HIGH = 4'd8;

    reg [3:0] state;
    reg [7:0] net_load_count [0:254];
    reg [7:0] net_index;
    reg [7:0] net_driver [0:254];
    reg [7:0] loads_remaining;
    reg [7:0] load_cell [0:254];
    reg [7:0] load_ptr;
    reg [7:0] net_load_start [0:254];

    always @(posedge clk) begin
        read_driver <= net_driver[read_net];
        read_load_count <= net_load_count[read_net];
        read_load_start <= net_load_start[read_net];
        read_load_cell <= load_cell[read_load];
        // Independent synchronous read port for the second HPWL lane.
        read_driver_1 <= net_driver[read_net_1];
        read_load_count_1 <= net_load_count[read_net_1];
        read_load_start_1 <= net_load_start[read_net_1];
        read_load_cell_1 <= load_cell[read_load_1];
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= WAITING_START;
            net_index <= 8'd0;
            cell_count <= 8'd0;
            net_count <= 8'd0;
            alpha <= 16'd32768;
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
                        state <= WAITING_ALPHA_LOW;
                    end
                end

                // After 0xAD: Q0.16 alpha, low byte then high byte; then payload.
                WAITING_ALPHA_LOW: begin
                    if (rx_valid) begin
                        alpha[7:0] <= rx_data;
                        state <= WAITING_ALPHA_HIGH;
                    end
                end

                WAITING_ALPHA_HIGH: begin
                    if (rx_valid) begin
                        alpha[15:8] <= rx_data;
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
