#include <stdio.h>
#include "pico/stdlib.h"
#include "hardware/adc.h"
#include "hardware/i2c.h"
#include "hardware/uart.h"
#include "ssd1306.h"
#include "netlist_data.h"

// OLED Defines
#define OLED_I2C i2c0
#define OLED_SDA 16
#define OLED_SCL 17
#define OLED_ADDRESS 0x3C
#define OLED_HEIGHT 64

// Button
#define BTN_PIN 11

// Potentiometer wiper on ADC0
#define ALPHA_ADC_PIN 26
#define ALPHA_ADC_INPUT 0

// UART to FPGA
#define FPGA_UART uart0
#define FPGA_UART_TX_PIN 0
#define FPGA_UART_RX_PIN 1
#define FPGA_UART_BAUD 115200

// LED
#define LED_PIN 18

int main(void) {
    stdio_init_all();

    // I2C for OLED
    i2c_init(OLED_I2C, 400 * 1000);
    gpio_set_function(OLED_SDA, GPIO_FUNC_I2C);
    gpio_set_function(OLED_SCL, GPIO_FUNC_I2C);
    gpio_pull_up(OLED_SDA);
    gpio_pull_up(OLED_SCL);
    sleep_ms(100);

    // Button setup
    gpio_init(BTN_PIN);
    gpio_set_dir(BTN_PIN, GPIO_IN);
    gpio_pull_up(BTN_PIN);

    // ADC
    adc_init();
    adc_gpio_init(ALPHA_ADC_PIN);
    adc_select_input(ALPHA_ADC_INPUT);

    // UART setup
    uart_init(FPGA_UART, FPGA_UART_BAUD);
    gpio_set_function(FPGA_UART_TX_PIN, GPIO_FUNC_UART);
    gpio_set_function(FPGA_UART_RX_PIN, GPIO_FUNC_UART);
    uart_set_fifo_enabled(FPGA_UART, true); // Buffer the reply during OLED updates.

    // LED setup
    gpio_init(LED_PIN);
    gpio_set_dir(LED_PIN, GPIO_OUT);

    ssd1306_t display;
    ssd1306_init(&display, OLED_I2C, OLED_ADDRESS, OLED_HEIGHT);

    bool button_pressed = false;
    uint8_t digits[4] = {0, 0, 0, 0};
    uint8_t selected_digit = 0;
    float filtered_adc = (float)adc_read();
    uint8_t last_knob_digit = (uint8_t)(filtered_adc * 10.0f / 4096.0f);
    digits[0] = last_knob_digit;
    const char *digit_labels[4] = {
        "0.X000", "0.0X00", "0.00X0", "0.000X"
    };

    while (true) {
        // Ten knob positions
        filtered_adc += ((float)adc_read() - filtered_adc) / 8.0f;
        float knob_position = filtered_adc * 10.0f / 4096.0f;
        uint8_t knob_digit = last_knob_digit;
        if (knob_position >= (float)(last_knob_digit + 1) + 0.1f ||
            knob_position < (float)last_knob_digit - 0.1f) {
            knob_digit = (uint8_t)knob_position;
        }

        bool pressed = gpio_get(BTN_PIN) == 0;
        if (pressed != button_pressed) {
            button_pressed = pressed;
            if (button_pressed) {
                digits[selected_digit] = knob_digit;
                uart_putc_raw(FPGA_UART, 0xAA);
                selected_digit = selected_digit + 1;
                if (selected_digit == 4) break;
                last_knob_digit = knob_digit;
                digits[selected_digit] = knob_digit;
            }
        }

        if (knob_digit != last_knob_digit) {
            digits[selected_digit] = knob_digit;
            last_knob_digit = knob_digit;
        }

        uint32_t alpha_digits = digits[0] * 1000 + digits[1] * 100 +
                                digits[2] * 10 + digits[3];
        char alpha_text[20];
        snprintf(alpha_text, sizeof(alpha_text), "ALPHA 0.%04lu", (unsigned long)alpha_digits);

        ssd1306_clear(&display);
        ssd1306_draw_text(&display, 0, 2, button_pressed ? "PRESSED" : "UNPRESSED");
        ssd1306_draw_text(&display, 0, 4, alpha_text);
        ssd1306_draw_text(&display, 0, 6, digit_labels[selected_digit]);
        ssd1306_show(&display);
        gpio_put(LED_PIN, button_pressed);
    }

    ssd1306_clear(&display);
    ssd1306_draw_text(&display, 0, 2, "NETLIST SENDING");
    ssd1306_show(&display);
    while (uart_is_readable(FPGA_UART))
        uart_getc(FPGA_UART);

    // Convert the four selected decimal digits to alpha * 65536, rounded.
    uint32_t alpha_digits = digits[0] * 1000 + digits[1] * 100 +
                            digits[2] * 10 + digits[3];
    uint16_t alpha_fixed = (uint16_t)((alpha_digits * 65536u + 5000u) / 10000u);

    // Wire format: 0xAD, alpha low byte, alpha high byte, original netlist.
    uart_putc_raw(FPGA_UART, 0xAD);
    uart_putc_raw(FPGA_UART, (uint8_t)alpha_fixed);
    uart_putc_raw(FPGA_UART, (uint8_t)(alpha_fixed >> 8));
    uart_write_blocking(FPGA_UART, netlist_data, sizeof(netlist_data));
    ssd1306_clear(&display);
    ssd1306_draw_text(&display, 0, 2, "ANNEALING...");
    ssd1306_show(&display);

    // FPGA returns the best cost, low byte first, followed by the high byte.
    uint8_t cost_low = uart_getc(FPGA_UART);
    uint8_t cost_high = uart_getc(FPGA_UART);
    uint16_t cost = (uint16_t)cost_low | ((uint16_t)cost_high << 8);

    char cost_text[20];
    snprintf(cost_text, sizeof(cost_text), "BEST HPWL %u", (unsigned int)cost);
    ssd1306_clear(&display);
    ssd1306_draw_text(&display, 0, 2, cost_text);
    ssd1306_show(&display);

    while (true)
        tight_loop_contents();
}
