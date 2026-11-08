`default_nettype none

module annealer #(
    parameter integer MOVES_PER_TEMP = 1,
    parameter [31:0] SEED = 32'h12345678
) (
    input wire clk,
    input wire rst,
    input wire start,
    input wire [7:0] cell_count,
    input wire [7:0] net_count,
    input wire [15:0] alpha,

    output wire [7:0] read_net,
    output wire [7:0] read_load,
    input wire [7:0] read_driver,
    input wire [7:0] read_load_count,
    input wire [7:0] read_load_start,
    input wire [7:0] read_load_cell,

    output wire [7:0] read_net_1,
    output wire [7:0] read_load_1,
    input wire [7:0] read_driver_1,
    input wire [7:0] read_load_count_1,
    input wire [7:0] read_load_start_1,
    input wire [7:0] read_load_cell_1,

    output wire [6:0] read_cell,
    input wire [7:0] read_position,
    output wire [6:0] read_cell_1,
    input wire [7:0] read_position_1,
    output reg write_enable,
    output reg [6:0] write_cell,
    output reg [7:0] write_position,

    input wire [6:0] read_best_cell,
    output reg [7:0] read_best_position,
    output reg [15:0] best_cost,
    output reg done
);

    localparam WAIT_START = 5'd0;
    localparam WAIT_EVAL_READY = 5'd1;
    localparam WAIT_EVAL_DONE = 5'd2;
    localparam WAIT_PROBABILITY = 5'd3;
    localparam DECIDE = 5'd4;
    localparam COMMIT_SECOND = 5'd5;
    localparam COMMIT_DONE = 5'd6;
    localparam WAIT_COPY = 5'd7;
    localparam COPY_BEST = 5'd8;
    localparam PICK_A = 5'd9;
    localparam WAIT_A = 5'd10;
    localparam READ_A = 5'd11;
    localparam PICK_B = 5'd12;
    localparam WAIT_B = 5'd13;
    localparam READ_B = 5'd14;
    localparam NEXT_PROPOSAL = 5'd15;
    localparam WAIT_RELEASE = 5'd16;
    localparam PREPARE_RATIO = 5'd17;
    localparam DIVIDE_RATIO = 5'd18;

    reg [4:0] state;
    reg [31:0] random_state;
    reg [23:0] temperature;
    reg [15:0] alpha_latched;
    reg [15:0] moves_at_temperature;
    reg [15:0] current_cost;
    reg [15:0] candidate_cost;

    reg [6:0] swap_a;
    reg [6:0] swap_b;
    reg [7:0] position_a;
    reg [7:0] position_b;
    reg swap_enable;
    reg initial_eval;
    reg new_best;

    reg eval_start;
    reg eval_active;
    reg [6:0] control_read_cell;
    wire [6:0] eval_read_cell;
    wire [15:0] eval_cost_0;
    wire [15:0] eval_cost_1;
    wire eval_done_0;
    wire eval_done_1;
    // Each lane holds its result until the next evaluation starts.
    wire [15:0] eval_cost = eval_cost_0 + eval_cost_1;
    wire eval_done = eval_done_0 && eval_done_1;

    reg [7:0] best_position [0:127];
    reg [6:0] copy_index;

    // Xorshift32. Each expression uses the result of the preceding shift.
    wire [31:0] random_step1 = random_state ^ (random_state << 13);
    wire [31:0] random_step2 = random_step1 ^ (random_step1 >> 17);
    wire [31:0] random_next = random_step2 ^ (random_step2 << 5);

    wire [15:0] delta = candidate_cost - current_cost;
    wire [15:0] probability;

    // Temperature is Q8.16: 100 * 65536. Alpha is Q0.16.
    // Extra fractional bits keep slow cooling accurate near T = 0.1.
    localparam [23:0] START_TEMPERATURE = 24'd6553600;
    localparam [23:0] END_TEMPERATURE = 24'd6554;
    wire [39:0] cooling_product = temperature * alpha_latched;
    wire [23:0] cooled_temperature = cooling_product[39:16];

    // Compute floor(64 * delta / T) with one division bit per clock.
    // Since T has 16 fractional bits, the numerator is delta << 22.
    reg [37:0] division_bits;
    reg [24:0] remainder;
    reg [5:0] division_count;
    reg [9:0] probability_index;
    reg probability_underflow;
    wire [24:0] trial_remainder = {remainder[23:0], division_bits[37]};
    wire subtract_temperature = trial_remainder >= {1'b0, temperature};
    wire [37:0] next_division_bits = {division_bits[36:0], subtract_temperature};

    // The evaluator owns the position read port while computing HPWL.
    assign read_cell = eval_active ? eval_read_cell : control_read_cell;

    hpwl_eval #(.FIRST_NET(0), .NET_STRIDE(2)) hpwl_inst (
        .clk(clk),
        .rst(rst),
        .start(eval_start),
        .net_count(net_count),
        .swap_enable(swap_enable),
        .swap_a(swap_a),
        .swap_b(swap_b),
        .position_a(position_a),
        .position_b(position_b),
        .read_net(read_net),
        .read_load(read_load),
        .read_driver(read_driver),
        .read_load_count(read_load_count),
        .read_load_start(read_load_start),
        .read_load_cell(read_load_cell),
        .read_cell(eval_read_cell),
        .read_position(read_position),
        .cost(eval_cost_0),
        .done(eval_done_0)
    );

    hpwl_eval #(.FIRST_NET(1), .NET_STRIDE(2)) hpwl_inst_1 (
        .clk(clk),
        .rst(rst),
        .start(eval_start),
        .net_count(net_count),
        .swap_enable(swap_enable),
        .swap_a(swap_a),
        .swap_b(swap_b),
        .position_a(position_a),
        .position_b(position_b),
        .read_net(read_net_1),
        .read_load(read_load_1),
        .read_driver(read_driver_1),
        .read_load_count(read_load_count_1),
        .read_load_start(read_load_start_1),
        .read_load_cell(read_load_cell_1),
        .read_cell(read_cell_1),
        .read_position(read_position_1),
        .cost(eval_cost_1),
        .done(eval_done_1)
    );

    acceptance_rom probability_inst (
        .clk(clk),
        .ratio_index(probability_index),
        .probability(probability)
    );

    always @(posedge clk) begin
        read_best_position <= best_position[read_best_cell];
        if (!rst && state == COPY_BEST)
            best_position[copy_index] <= read_position;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= WAIT_START;
            random_state <= SEED;
            temperature <= START_TEMPERATURE;
            alpha_latched <= 16'd32768;
            division_bits <= 38'd0;
            remainder <= 25'd0;
            division_count <= 6'd0;
            probability_index <= 10'd0;
            probability_underflow <= 1'b0;
            moves_at_temperature <= 16'd0;
            current_cost <= 16'd0;
            candidate_cost <= 16'd0;
            best_cost <= 16'd0;
            done <= 1'b0;
            swap_a <= 7'd0;
            swap_b <= 7'd0;
            position_a <= 8'd0;
            position_b <= 8'd0;
            swap_enable <= 1'b0;
            initial_eval <= 1'b0;
            new_best <= 1'b0;
            eval_start <= 1'b0;
            eval_active <= 1'b0;
            control_read_cell <= 7'd0;
            copy_index <= 7'd0;
            write_enable <= 1'b0;
            write_cell <= 7'd0;
            write_position <= 8'd0;
        end else begin
            random_state <= random_next;
            eval_start <= 1'b0;
            write_enable <= 1'b0;

            case (state)
                WAIT_START: begin
                    if (start) begin
                        random_state <= SEED;
                        temperature <= START_TEMPERATURE;
                        alpha_latched <= alpha;
                        moves_at_temperature <= 16'd0;
                        done <= 1'b0;
                        swap_enable <= 1'b0;
                        initial_eval <= 1'b1;
                        eval_active <= 1'b1;
                        eval_start <= 1'b1;
                        state <= WAIT_EVAL_READY;
                    end
                end

                // HPWL done stays high after a previous evaluation. Wait for
                // the new start pulse to clear it before accepting a result.
                WAIT_EVAL_READY: begin
                    if (!eval_done)
                        state <= WAIT_EVAL_DONE;
                end

                WAIT_EVAL_DONE: begin
                    if (eval_done) begin
                        eval_active <= 1'b0;
                        if (initial_eval) begin
                            current_cost <= eval_cost;
                            best_cost <= eval_cost;
                            copy_index <= 7'd0;
                            control_read_cell <= 7'd0;
                            state <= WAIT_COPY;
                        end else begin
                            candidate_cost <= eval_cost;
                            state <= PREPARE_RATIO;
                        end
                    end
                end

                PREPARE_RATIO: begin
                    if (candidate_cost <= current_cost) begin
                        state <= DECIDE;
                    end else begin
                        division_bits <= {delta, 22'd0};
                        remainder <= 25'd0;
                        division_count <= 6'd0;
                        state <= DIVIDE_RATIO;
                    end
                end

                DIVIDE_RATIO: begin
                    division_bits <= next_division_bits;
                    remainder <= subtract_temperature ?
                        trial_remainder - {1'b0, temperature} : trial_remainder;
                    if (division_count == 6'd37) begin
                        probability_index <= next_division_bits[9:0];
                        probability_underflow <= next_division_bits >= 38'd1024;
                        state <= WAIT_PROBABILITY;
                    end else begin
                        division_count <= division_count + 6'd1;
                    end
                end

                // The ROM reads the newly registered index on this edge;
                // DECIDE sees that result on the following edge.
                WAIT_PROBABILITY: state <= DECIDE;

                DECIDE: begin
                    // exp(-16) is below the ROM's 1/65536 resolution.
                    if (candidate_cost <= current_cost ||
                        (!probability_underflow &&
                         random_state[31:16] < probability)) begin
                        current_cost <= candidate_cost;
                        new_best <= candidate_cost < best_cost;
                        write_cell <= swap_a;
                        write_position <= position_b;
                        write_enable <= 1'b1;
                        state <= COMMIT_SECOND;
                    end else begin
                        state <= NEXT_PROPOSAL;
                    end
                end

                COMMIT_SECOND: begin
                    // The memory writes A on this edge; schedule B next.
                    write_cell <= swap_b;
                    write_position <= position_a;
                    write_enable <= 1'b1;
                    state <= COMMIT_DONE;
                end

                COMMIT_DONE: begin
                    // B is written on this edge. A later read sees both writes.
                    if (new_best) begin
                        best_cost <= candidate_cost;
                        copy_index <= 7'd0;
                        control_read_cell <= 7'd0;
                        state <= WAIT_COPY;
                    end else begin
                        state <= NEXT_PROPOSAL;
                    end
                end

                WAIT_COPY: state <= COPY_BEST;

                COPY_BEST: begin
                    // The separate memory block saves this cell on this edge.
                    // Proposals pause until the entire best snapshot is saved.
                    if (copy_index == cell_count - 8'd1) begin
                        if (initial_eval) begin
                            initial_eval <= 1'b0;
                            state <= PICK_A;
                        end else begin
                            state <= NEXT_PROPOSAL;
                        end
                    end else begin
                        copy_index <= copy_index + 7'd1;
                        control_read_cell <= copy_index + 7'd1;
                        state <= WAIT_COPY;
                    end
                end

                PICK_A: begin
                    if (cell_count < 8'd2) begin
                        // There is no distinct pair to swap in a one-cell file.
                        done <= 1'b1;
                        state <= WAIT_RELEASE;
                    end else if ({1'b0, random_state[6:0]} < cell_count) begin
                        swap_a <= random_state[6:0];
                        control_read_cell <= random_state[6:0];
                        state <= WAIT_A;
                    end
                end

                WAIT_A: state <= READ_A;

                READ_A: begin
                    position_a <= read_position;
                    state <= PICK_B;
                end

                PICK_B: begin
                    // Reject out-of-range IDs and A itself; no modulo bias.
                    if ({1'b0, random_state[6:0]} < cell_count &&
                        random_state[6:0] != swap_a) begin
                        swap_b <= random_state[6:0];
                        control_read_cell <= random_state[6:0];
                        state <= WAIT_B;
                    end
                end

                WAIT_B: state <= READ_B;

                READ_B: begin
                    position_b <= read_position;
                    swap_enable <= 1'b1;
                    eval_active <= 1'b1;
                    eval_start <= 1'b1;
                    state <= WAIT_EVAL_READY;
                end

                NEXT_PROPOSAL: begin
                    // Count accepted AND rejected proposals toward cooling.
                    if (moves_at_temperature == MOVES_PER_TEMP - 1) begin
                        moves_at_temperature <= 16'd0;
                        if (cooled_temperature <= END_TEMPERATURE) begin
                            done <= 1'b1;
                            state <= WAIT_RELEASE;
                        end else begin
                            temperature <= cooled_temperature;
                            state <= PICK_A;
                        end
                    end else begin
                        moves_at_temperature <= moves_at_temperature + 16'd1;
                        state <= PICK_A;
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
