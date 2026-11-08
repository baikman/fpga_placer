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
        .read_load_cell(load_cell)
    );

    wire placement_done;
    wire [5:0] position_read_address;
    wire [5:0] position_read_data;
    wire position_write_enable;
    wire [5:0] position_write_address;
    wire [5:0] position_write_data;

    wire [15:0] best_cost;
    wire anneal_done;
    // Preserve the best-coordinate memory until the coordinate sender is added.
    (* keep = "true" *) wire [5:0] best_position_data;

    placement_init placement_inst (
        .clk(clk),
        .rst(rst),
        .start(netlist_done),
        .cell_count(loaded_cell_count),
        .done(placement_done),
        .read_cell(position_read_address),
        .read_position(position_read_data),
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
        .read_load_cell(load_cell),
        .read_cell(position_read_address),
        .read_position(position_read_data),
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

    reg [1:0] tx_state;
    reg [7:0] cost_high;
    reg sending_high;

    // Return two bytes: cost[7:0], then cost[15:8].
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state <= WAIT_COST;
            tx_data <= 8'd0;
            tx_start <= 1'b0;
            cost_high <= 8'd0;
            sending_high <= 1'b0;
        end else begin
            tx_start <= 1'b0;

            case (tx_state)
                WAIT_COST: begin
                    if (anneal_done && !tx_busy) begin
                        tx_data <= best_cost[7:0];
                        cost_high <= best_cost[15:8];
                        sending_high <= 1'b0;
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
                        if (!sending_high) begin
                            tx_data <= cost_high;
                            sending_high <= 1'b1;
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
