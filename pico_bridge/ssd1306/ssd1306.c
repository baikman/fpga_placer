// Adapted from the Raspberry Pi Pico SSD1306 I2C example (BSD-3-Clause).
// See LICENSE.TXT and ssd1306_font.h for the upstream copyright notice.
#include "ssd1306.h"

#include <stddef.h>
#include <string.h>
#include "ssd1306_font.h"

static bool write_commands(ssd1306_t *display, const uint8_t *commands, size_t size) {
    return i2c_write_blocking(display->i2c, display->address, commands, size, false) == (int)size;
}

void ssd1306_clear(ssd1306_t *display) {
    memset(display->buffer, 0, SSD1306_WIDTH * display->height / 8);
}

bool ssd1306_show(ssd1306_t *display) {
    const uint8_t window[] = {0x00, 0x21, 0, SSD1306_WIDTH - 1,
                              0x22, 0, (uint8_t)(display->height / 8 - 1)};
    if (!write_commands(display, window, sizeof window)) {
        return false;
    }

    uint8_t packet[1 + SSD1306_WIDTH];
    packet[0] = 0x40; // Following bytes are display RAM data.
    const size_t length = SSD1306_WIDTH * display->height / 8;
    for (size_t offset = 0; offset < length; offset += SSD1306_WIDTH) {
        memcpy(packet + 1, display->buffer + offset, SSD1306_WIDTH);
        if (i2c_write_blocking(display->i2c, display->address, packet,
                               sizeof packet, false) != (int)sizeof packet) {
            return false;
        }
    }
    return true;
}

bool ssd1306_init(ssd1306_t *display, i2c_inst_t *i2c, uint8_t address, uint8_t height) {
    if (display == NULL || i2c == NULL || (height != 32 && height != 64)) {
        return false;
    }

    display->i2c = i2c;
    display->address = address;
    display->height = height;

    const uint8_t init[] = {
        0x00,       // The following bytes are commands.
        0xAE,       // Display off.
        0xD5, 0x80, // Clock divide ratio.
        0xA8, (uint8_t)(height - 1), // Multiplex ratio.
        0xD3, 0x00, // Display offset.
        0x40,       // Start line 0.
        0x8D, 0x14, // Enable internal charge pump.
        0x20, 0x00, // Horizontal memory addressing.
        0xA0,       // Segment remap.
        0xC0,       // COM scan direction.
        0xDA, (uint8_t)(height == 64 ? 0x12 : 0x02), // COM pin configuration.
        0x81, 0x7F, // Contrast.
        0xD9, 0xF1, // Precharge period.
        0xDB, 0x30, // VCOMH level.
        0xA4,       // Display follows RAM contents.
        0xA6,       // Normal, non-inverted display.
        0x2E        // Disable scrolling.
    };
    if (!write_commands(display, init, sizeof init)) {
        return false;
    }

    ssd1306_clear(display);
    if (!ssd1306_show(display)) {
        return false;
    }
    const uint8_t display_on[] = {0x00, 0xAF};
    return write_commands(display, display_on, sizeof display_on);
}

void ssd1306_draw_text(ssd1306_t *display, uint8_t x, uint8_t page, const char *text) {
    if (page >= display->height / 8 || text == NULL) {
        return;
    }

    size_t column = x;
    while (*text != '\0' && column + 8 <= SSD1306_WIDTH) {
        unsigned char ch = (unsigned char)*text++;
        if (ch >= 'a' && ch <= 'z') {
            ch -= 'a' - 'A';
        }

        size_t glyph = 0; // Unsupported characters become spaces.
        if (ch >= 'A' && ch <= 'Z') {
            glyph = ch - 'A' + 1;
        } else if (ch >= '0' && ch <= '9') {
            glyph = ch - '0' + 27;
        } else if (ch == '.') {
            glyph = 37;
        }
        memcpy(display->buffer + page * SSD1306_WIDTH + column,
               font + glyph * 8, 8);
        column += 8;
    }
}
