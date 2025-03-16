/*
 vga.c
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: VGA driver and text functions implementation
 Copyright (c) 2025 Maxims Enterprise
*/

#include "vga.h"
#include "common.h"
#include "drivers/serial.h"

u16 *textmemptr;
int attrib = 0x0F;
int csr_x = 0, csr_y = 0;

void scroll() {
    unsigned blank, temp;
    blank = 0x20 | (attrib << 8);

    if (csr_y >= VGA_HEIGHT) {
        temp = csr_y - VGA_HEIGHT + 1;

        memcopy((u8 *)textmemptr, (u8 *)textmemptr + temp * VGA_WIDTH * 2,
                (VGA_HEIGHT - temp) * VGA_WIDTH * 2);

        memset_w(textmemptr + (VGA_HEIGHT - temp) * VGA_WIDTH, blank,
                 temp * VGA_WIDTH);

        csr_y = VGA_HEIGHT - 1;
    }
}

void move_csr() {
    u16 temp;

    temp = csr_y * VGA_WIDTH + csr_x;

    outb(0x3D4, 14);
    outb(0x3D5, temp >> 8);
    outb(0x3D4, 15);
    outb(0x3D5, temp);
}

void clear() {
    u16 blank;
    int i;

    blank = 0x20 | (attrib << 8);

    for (i = 0; i < VGA_HEIGHT; i++)
        memset_w(textmemptr + i * VGA_WIDTH, blank, VGA_WIDTH);

    csr_x = 0;
    csr_y = 0;
    move_csr();
}

void write_char(char c) {
#ifndef NOGRAPHIC
    serial_write(c);
    return;
#endif
    u16 *pos;
    unsigned att = attrib << 8;

    if (c == 0x08) {
        if (csr_x != 0) {
            csr_x--;
            pos = textmemptr + (csr_y * VGA_WIDTH + csr_x);
            *pos = ' ' | att;
        }
    } else if (c == 0x09) {
        csr_x = (csr_x + 8) & ~(8 - 1);
    } else if (c == '\r') {
        csr_x = 0;
    } else if (c == '\n') {
        csr_x = 0;
        csr_y++;
    } else if (c >= ' ') {
        pos = textmemptr + (csr_y * VGA_WIDTH + csr_x);
        *pos = c | att;
        csr_x++;
    }

    if (csr_x >= VGA_WIDTH) {
        csr_x = 0;
        csr_y++;
    }

    scroll();
    move_csr();
}

void write(str s) {
#ifndef NOGRAPHIC
    serial_write_str(s);
    return;
#endif
    u32 i;

    for (i = 0; i < strlen(s); i++)
        write_char(s[i]);
}

void set_text_color(VGATextColor fg, VGATextColor bg) {
    attrib = (bg << 4) | fg;
}

void init_vga() {
    textmemptr = (u16 *)0xB8000;
    clear();
}
