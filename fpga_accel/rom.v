`default_nettype  none

module rom (
    input wire [3:0] address,
    output reg [15:0] instruction
);

    always @(*) begin
        case (address)
            4'd0: instruction = 16'h0105;
            4'd1: instruction = 16'h0203;
            4'd2: instruction = 16'h0600;
            4'd3: instruction = 16'hFF00; 
            default: instruction = 16'h0000;
        endcase
    end

endmodule
