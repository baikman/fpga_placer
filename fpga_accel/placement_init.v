`default_nettype  none

module placement_init (
    input wire clk,
    input wire rst,
    input wire start,
    input wire [7:0] cell_count,
    input wire [6:0] read_cell,
    input wire [6:0] read_cell_1,
    input wire write_enable,
    input wire [6:0] write_cell,
    input wire [7:0] write_position,

    output reg [7:0] read_position,
    output reg [7:0] read_position_1,
    output reg done
);
    
    reg [7:0] position [0:127];
    reg [6:0] cell_index;
    reg [3:0] x;
    reg [3:0] y;
    reg [3:0] side;

    localparam WAIT_START = 2'd0;
    localparam FILL = 2'd1;
    localparam WAIT_RELEASE = 2'd2;

    reg [1:0] state;

    always @(*) begin
        if (cell_count <= 8'd1) side = 4'd1;
        else if (cell_count <= 8'd4) side = 4'd2;
        else if (cell_count <= 8'd9) side = 4'd3;
        else if (cell_count <= 8'd16) side = 4'd4;
        else if (cell_count <= 8'd25) side = 4'd5;
        else if (cell_count <= 8'd36) side = 4'd6;
        else if (cell_count <= 8'd49) side = 4'd7;
        else if (cell_count <= 8'd64) side = 4'd8;
        else if (cell_count <= 8'd81) side = 4'd9;
        else if (cell_count <= 8'd100) side = 4'd10;
        else if (cell_count <= 8'd121) side = 4'd11;
        else side = 4'd12;
    end

    always @(posedge clk) begin
        read_position <= position[read_cell];
        read_position_1 <= position[read_cell_1];

        // Both initialization and accepted swaps use the same write port.
        if (!rst) begin
            if (state == FILL)
                position[cell_index] <= {x, y};
            else if (write_enable)
                position[write_cell] <= write_position;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= WAIT_START;
            cell_index <= 7'd0;
            x <= 4'd0;
            y <= 4'd0;
            done <= 1'b0;
        end else begin
            case (state)
                WAIT_START: begin
                    if (start) begin
                        cell_index <= 7'd0;
                        x <= 4'd0;
                        y <= 4'd0;
                        done <= 1'b0;
                        state <= FILL;
                    end
                end

                FILL: begin
                    if (cell_index == cell_count - 8'd1) begin
                        done <= 1'b1;
                        state <= WAIT_RELEASE;
                    end else begin
                        cell_index <= cell_index + 7'd1;

                        if (y == side - 4'd1) begin
                            y <= 4'd0;
                            x <= x + 4'd1;
                        end else begin
                            y <= y + 4'd1;
                        end
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
