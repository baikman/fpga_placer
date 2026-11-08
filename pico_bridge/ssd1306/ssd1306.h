#ifndef SSD1306_H
#define SSD1306_H

#include <stdbool.h>
#include <stdint.h>
#include "hardware/i2c.h"

#define SSD1306_WIDTH 128

typedef struct {
    i2c_inst_t *i2c;
    uint8_t address;
    uint8_t height;
    uint8_t buffer[SSD1306_WIDTH * 64 / 8];
} ssd1306_t;

// The I2C bus and its pins must be initialized before calling this.
// Supports 128x32 and 128x64 displays with an internal charge pump.
bool ssd1306_init(ssd1306_t *display, i2c_inst_t *i2c, uint8_t address, uint8_t height);
void ssd1306_clear(ssd1306_t *display);
// Text is 8 pixels high; page 0 starts at the top of the display.
void ssd1306_draw_text(ssd1306_t *display, uint8_t x, uint8_t page, const char *text);
bool ssd1306_show(ssd1306_t *display);

#endif
