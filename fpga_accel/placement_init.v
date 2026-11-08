`default_nettype  none

module placement_init (
    input wire clk,
    input wire rst,
    input wire start,
    input wire [7:0] cell_count,

    output reg done
);
    
    reg [5:0] position [0:63];
    reg [5:0] cell_index;
    reg [2:0] x;
    reg [2:0] y;
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
        else side = 4'd8;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= WAIT_START;
            cell_index <= 6'd0;
            x <= 3'd0;
            y <= 3'd0;
            done <= 1'b0;
        end else begin
            case (state)
                WAIT_START: begin
                    if (start) begin
                        cell_index <= 6'd0;
                        x <= 3'd0;
                        y <= 3'd0;
                        done <= 1'b0;
                        state <= FILL;
                    end
                end

                FILL: begin
                    position[cell_index] <= {x, y};

                    if (cell_index == cell_count - 8'd1) begin
                        done <= 1'b1;
                        state <= WAIT_RELEASE;
                    end else begin
                        cell_index <= cell_index + 6'd1;

                        if (y == side - 4'd1) begin
                            y <= 3'd0;
                            x <= x + 3'd1;
                        end else begin
                            y <= y + 3'd1;
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