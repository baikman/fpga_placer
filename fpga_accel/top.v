`default_nettype none

module top (
    input wire clk,
    input wire rst,
    input wire uart_rx,
    output reg led,
    output wire uart_tx
);

    wire [3:0] rom_address;
    wire [15:0] instruction;
    wire [7:0] tx_data;
    wire tx_start;
    wire tx_busy;
    wire [7:0] rx_data;
    wire rx_valid;

    cpu cpu_inst (
        .clk(clk),
        .rst(rst),
        .rom_address(rom_address),
        .instruction(instruction),
        .debug_acc(),

        .tx_data(tx_data),
        .tx_start(tx_start),
        .tx_busy(tx_busy)
    );

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

    rom rom_inst (
        .address(rom_address),
        .instruction(instruction)
    );

    always @(posedge clk or posedge rst) begin
        if (rst)
            led <= 1'b0;
        else if (rx_valid && rx_data == 8'hAA)
            led <= ~led;
    end

endmodule
