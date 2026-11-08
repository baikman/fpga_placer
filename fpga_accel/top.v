`default_nettype none

module top (
    input wire clk,
    input wire rst,
    input wire uart_rx,
    output reg led,
    output wire uart_tx
);

    reg [7:0] tx_data;
    reg tx_start;
    wire tx_busy;
    wire [7:0] rx_data;
    wire rx_valid;

    uart_tx #(
        .CLKS_PER_BIT(868)
    ) uart_inst (
        .clk(clk),
        .rst(rst),
        .data(tx_data),
        .start(tx_start),
        .tx(uart_tx),
        .busy(tx_busy)
    );

    uart_rx #(
        .CLKS_PER_BIT(868)
    ) uart_rx_inst (
        .clk(clk),
        .rst(rst),
        .rx(uart_rx),
        .data(rx_data),
        .valid(rx_valid)
    );

    wire loader_start = rx_valid && (rx_data == 8'hAD);
    wire [7:0] loaded_cell_count;
    wire [7:0] loaded_net_count;
    wire [15:0] loaded_alpha;
    wire netlist_done;
    wire [7:0] net_read_address;
    wire [7:0] load_read_address;
    wire [7:0] net_driver;
    wire [7:0] net_load_count;
    wire [7:0] net_load_start;
    wire [7:0] load_cell;
    wire [7:0] net_read_address_1;
    wire [7:0] load_read_address_1;
    wire [7:0] net_driver_1;
    wire [7:0] net_load_count_1;
    wire [7:0] net_load_start_1;
    wire [7:0] load_cell_1;

    netlist_loader loader_inst (
        .clk(clk),
        .rst(rst),
        .start(loader_start),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .cell_count(loaded_cell_count),
        .net_count(loaded_net_count),
        .alpha(loaded_alpha),
        .done(netlist_done),
        .read_net(net_read_address),
        .read_load(load_read_address),
        .read_driver(net_driver),
        .read_load_count(net_load_count),
        .read_load_start(net_load_start),
        .read_net_1(net_read_address_1),
        .read_load_1(load_read_address_1),
        .read_driver_1(net_driver_1),
        .read_load_count_1(net_load_count_1),
        .read_load_start_1(net_load_start_1),
        .read_load_cell_1(load_cell_1),
        .read_load_cell(load_cell)
    );

    wire placement_done;
    wire [6:0] position_read_address;
    wire [7:0] position_read_data;
    wire [6:0] position_read_address_1;
    wire [7:0] position_read_data_1;
    wire position_write_enable;
    wire [6:0] position_write_address;
    wire [7:0] position_write_data;

    wire [15:0] best_cost;
    wire anneal_done;
    // Preserve the best-coordinate memory until the coordinate sender is added.
    (* keep = "true" *) wire [7:0] best_position_data;

    placement_init placement_inst (
        .clk(clk),
        .rst(rst),
        .start(netlist_done),
        .cell_count(loaded_cell_count),
        .done(placement_done),
        .read_cell(position_read_address),
        .read_position(position_read_data),
        .read_cell_1(position_read_address_1),
        .read_position_1(position_read_data_1),
        .write_enable(position_write_enable),
        .write_cell(position_write_address),
        .write_position(position_write_data)
    );

    annealer anneal_inst (
        .clk(clk),
        .rst(rst),
        .start(placement_done),
        .cell_count(loaded_cell_count),
        .net_count(loaded_net_count),
        .alpha(loaded_alpha),
        .read_net(net_read_address),
        .read_load(load_read_address),
        .read_driver(net_driver),
        .read_load_count(net_load_count),
        .read_load_start(net_load_start),
        .read_net_1(net_read_address_1),
        .read_load_1(load_read_address_1),
        .read_driver_1(net_driver_1),
        .read_load_count_1(net_load_count_1),
        .read_load_start_1(net_load_start_1),
        .read_load_cell_1(load_cell_1),
        .read_load_cell(load_cell),
        .read_cell(position_read_address),
        .read_position(position_read_data),
        .read_cell_1(position_read_address_1),
        .read_position_1(position_read_data_1),
        .write_enable(position_write_enable),
        .write_cell(position_write_address),
        .write_position(position_write_data),
        .read_best_cell(position_read_address),
        .read_best_position(best_position_data),
        .best_cost(best_cost),
        .done(anneal_done)
    );

    localparam WAIT_COST = 2'd0;
    localparam WAIT_TX_BUSY = 2'd1;
    localparam WAIT_TX_DONE = 2'd2;
    localparam WAIT_COST_RELEASE = 2'd3;

    reg netlist_done_previous;
    reg timing_active;
    reg [63:0] elapsed_cycles;

    // Start on the same edge that placement_init accepts netlist_done.
    // Stop when annealer asserts done; the observing edge adds no cycle.
    // Loading and transmitting the result are outside this interval.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            netlist_done_previous <= 1'b0;
            timing_active <= 1'b0;
            elapsed_cycles <= 64'd0;
        end else begin
            netlist_done_previous <= netlist_done;
            if (netlist_done && !netlist_done_previous) begin
                elapsed_cycles <= 64'd0;
                timing_active <= 1'b1;
            end else if (timing_active) begin
                if (anneal_done)
                    timing_active <= 1'b0;
                else
                    elapsed_cycles <= elapsed_cycles + 64'd1;
            end
        end
    end

    reg [1:0] tx_state;
    reg [79:0] reply_data;
    reg [3:0] reply_index;

    // Return cost (2 bytes), then elapsed cycles (8 bytes), both low byte first.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state <= WAIT_COST;
            tx_data <= 8'd0;
            tx_start <= 1'b0;
            reply_data <= 80'd0;
            reply_index <= 4'd0;
        end else begin
            tx_start <= 1'b0;

            case (tx_state)
                WAIT_COST: begin
                    if (anneal_done && !timing_active && !tx_busy) begin
                        tx_data <= best_cost[7:0];
                        reply_data <= {elapsed_cycles, best_cost};
                        reply_index <= 4'd0;
                        tx_start <= 1'b1;
                        tx_state <= WAIT_TX_BUSY;
                    end
                end

                // busy rises after the UART samples our start pulse.
                WAIT_TX_BUSY: begin
                    if (tx_busy)
                        tx_state <= WAIT_TX_DONE;
                end

                WAIT_TX_DONE: begin
                    if (!tx_busy) begin
                        if (reply_index != 4'd9) begin
                            tx_data <= reply_data[15:8];
                            reply_data <= {8'd0, reply_data[79:8]};
                            reply_index <= reply_index + 4'd1;
                            tx_start <= 1'b1;
                            tx_state <= WAIT_TX_BUSY;
                        end else begin
                            tx_state <= WAIT_COST_RELEASE;
                        end
                    end
                end

                WAIT_COST_RELEASE: begin
                    if (!anneal_done)
                        tx_state <= WAIT_COST;
                end

                default: tx_state <= WAIT_COST;
            endcase
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst)
            led <= 1'b0;
        else if (rx_valid && rx_data == 8'hAA)
            led <= ~led;
    end

endmodule
