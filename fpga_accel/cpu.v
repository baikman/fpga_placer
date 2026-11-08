`default_nettype none

module cpu (
    input wire clk,
    input wire rst,

    output wire [3:0] rom_address,
    input wire [15:0] instruction,

    output wire [7:0] debug_acc,

    output reg [7:0] tx_data,
    output reg tx_start,
    input wire tx_busy
);
    reg [7:0] ACC;
    reg [3:0] PC;
    reg [15:0] IR;
    reg zero;

    localparam FETCH = 2'd0;
    localparam EXECUTE = 2'd1;
    localparam WAIT_TX = 2'd2;
    localparam HALT = 2'd3;

    reg [1:0] state;
    
    reg tx_seen_busy;

    assign rom_address = PC;
    assign debug_acc = ACC;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ACC <= 8'h00;
            PC <= 4'h0;
            IR <= 16'h0000;
            zero <= 1'b0;
            tx_data <= 8'd0;
            tx_start <= 1'b0;
            tx_seen_busy <= 0;
            state <= FETCH;
        end else begin
            case (state)
                FETCH: begin
                    IR <= instruction;
                    PC <= PC + 1;
                    state <= EXECUTE;
                end

                EXECUTE: begin
                    case (IR[15:8])

                        // LDI
                        8'h01: begin
                            ACC <= IR[7:0];
                            zero <= (IR[7:0] == 8'b0);
                            state <= FETCH;
                        end 

                        // ADDI
                        8'h02: begin
                            ACC <= (ACC + IR[7:0]);
                            zero <= ((ACC + IR[7:0]) == 8'b0);
                            state <= FETCH;
                        end

                        // HLT
                        8'hFF: begin
                            state <= HALT;
                        end

                        // OUT
                        8'h06: begin
                            tx_seen_busy <= 1'b0;
                            if (tx_busy == 0) begin
                                tx_data <= ACC;
                                tx_start <= 1'b1;
                                state <= WAIT_TX;
                            end
                        end
                        default: begin
                            state <= HALT;
                        end
                    endcase
                end

                WAIT_TX: begin
                    tx_start <= 1'b0;

                    if (tx_busy == 1'b1) begin
                        tx_seen_busy <= 1'b1;
                    end

                    if ((tx_seen_busy == 1) && (tx_busy == 0)) begin
                        state <= FETCH;
                    end
                end

                HALT: begin
                    state <= HALT;
                end 

                default: begin
                    state <= HALT;
                end
            endcase
        end
    end

endmodule
