`default_nettype none

module hpwl_eval #(
    parameter integer FIRST_NET = 0,
    parameter integer NET_STRIDE = 1
) (
    input wire clk,
    input wire rst,
    input wire start,
    input wire [7:0] net_count,

    input wire swap_enable,
    input wire [6:0] swap_a,
    input wire [6:0] swap_b,
    input wire [7:0] position_a,
    input wire [7:0] position_b,

    output reg [7:0] read_net,
    output reg [7:0] read_load,
    input wire [7:0] read_driver,
    input wire [7:0] read_load_count,
    input wire [7:0] read_load_start,
    input wire [7:0] read_load_cell,

    output reg [6:0] read_cell,
    input wire [7:0] read_position,

    output reg [15:0] cost,
    output reg done
);

    localparam WAIT_START = 4'd0;
    localparam WAIT_NET = 4'd1;
    localparam USE_NET = 4'd2;
    localparam WAIT_LOAD = 4'd3;
    localparam USE_LOAD = 4'd4;
    localparam WAIT_POSITION = 4'd5;
    localparam USE_POSITION = 4'd6;
    localparam FINISH_NET = 4'd7;
    localparam WAIT_RELEASE = 4'd8;

    reg [3:0] state;
    reg [7:0] loads_remaining;
    reg have_endpoint;
    reg [3:0] min_x;
    reg [3:0] max_x;
    reg [3:0] min_y;
    reg [3:0] max_y;

    // Evaluate a candidate without modifying current placement memory.
    // read_cell stays stable through WAIT_POSITION and USE_POSITION.
    wire [7:0] candidate_position =
        (swap_enable && read_cell == swap_a) ? position_b :
        (swap_enable && read_cell == swap_b) ? position_a : read_position;
    wire [3:0] x = candidate_position[7:4];
    wire [3:0] y = candidate_position[3:0];

    // Widen before arithmetic so the two spans and total cannot truncate.
    wire [15:0] net_cost = have_endpoint ?
        ({12'd0, max_x} - {12'd0, min_x}) +
        ({12'd0, max_y} - {12'd0, min_y}) : 16'd0;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= WAIT_START;
            read_net <= 8'd0;
            read_load <= 8'd0;
            read_cell <= 7'd0;
            loads_remaining <= 8'd0;
            have_endpoint <= 1'b0;
            min_x <= 4'd0;
            max_x <= 4'd0;
            min_y <= 4'd0;
            max_y <= 4'd0;
            cost <= 16'd0;
            done <= 1'b0;
        end else begin
            case (state)
                WAIT_START: begin
                    if (start) begin
                        read_net <= FIRST_NET;
                        cost <= 16'd0;
                        // A lane may have no nets, e.g. odd lane with one net.
                        done <= FIRST_NET >= net_count;
                        state <= (FIRST_NET >= net_count) ? WAIT_RELEASE : WAIT_NET;
                    end
                end

                // Address was set on the previous edge. Data updates on this
                // edge, so use it in the following state.
                WAIT_NET: state <= USE_NET;

                USE_NET: begin
                    loads_remaining <= read_load_count;
                    read_load <= read_load_start;
                    have_endpoint <= 1'b0;

                    if (read_driver != 8'hFF) begin
                        read_cell <= read_driver[6:0];
                        state <= WAIT_POSITION;
                    end else if (read_load_count != 8'd0) begin
                        state <= WAIT_LOAD;
                    end else begin
                        state <= FINISH_NET;
                    end
                end

                WAIT_LOAD: state <= USE_LOAD;

                USE_LOAD: begin
                    read_cell <= read_load_cell[6:0];
                    read_load <= read_load + 8'd1;
                    loads_remaining <= loads_remaining - 8'd1;
                    state <= WAIT_POSITION;
                end

                WAIT_POSITION: state <= USE_POSITION;

                USE_POSITION: begin
                    // The first endpoint seeds all four bounds. A single
                    // endpoint therefore has zero span in both directions.
                    if (!have_endpoint) begin
                        min_x <= x;
                        max_x <= x;
                        min_y <= y;
                        max_y <= y;
                        have_endpoint <= 1'b1;
                    end else begin
                        if (x < min_x) min_x <= x;
                        if (x > max_x) max_x <= x;
                        if (y < min_y) min_y <= y;
                        if (y > max_y) max_y <= y;
                    end

                    if (loads_remaining != 8'd0)
                        state <= WAIT_LOAD;
                    else
                        state <= FINISH_NET;
                end

                FINISH_NET: begin
                    // Bounds now include the final endpoint from the previous
                    // clock, so its contribution is included in net_cost.
                    cost <= cost + net_cost;
                    if (read_net + NET_STRIDE >= net_count) begin
                        done <= 1'b1;
                        state <= WAIT_RELEASE;
                    end else begin
                        read_net <= read_net + NET_STRIDE;
                        state <= WAIT_NET;
                    end
                end

                WAIT_RELEASE: begin
                    if (!start)
                        state <= WAIT_START;
                end

                default: state <= WAIT_START;
            endcase
        end
    end

endmodule
