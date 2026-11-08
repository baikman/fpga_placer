`default_nettype none

module acceptance_rom (
    input wire clk,
    input wire [9:0] ratio_index,
    output reg [15:0] probability
);

    reg [15:0] thresholds [0:1023];

    // Entry i approximates exp(-i/64), independent of temperature range.
    initial begin
        $readmemh("acceptance.hex", thresholds);
    end

    always @(posedge clk) begin
        probability <= thresholds[ratio_index];
    end

endmodule
