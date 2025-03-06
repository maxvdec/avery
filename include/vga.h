/*
 vga.h
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: VGA functions working with Text Interface
 Copyright (c) 2025 Maxims Enterprise
*/

#ifndef _VGA_H
#define _VGA_H

#include "common.h"

#define VGA_WIDTH 80
#define VGA_HEIGHT 25

extern u16 *textmemptr;
extern int attrib;
extern int csr_x, csr_y;

typedef enum VGATextColor {
    BLACK = 0,
    BLUE = 1,
    GREEN = 2,
    CYAN = 3,
    RED = 4,
    MAGENTA = 5,
    BROWN = 6,
    LIGHT_GREY = 7,
    DARK_GREY = 8,
    LIGHT_BLUE = 9,
    LIGHT_GREEN = 10,
    LIGHT_CYAN = 11,
    LIGHT_RED = 12,
    LIGHT_MAGENTA = 13,
    LIGHT_BROWN = 14,
    WHITE = 15
} VGATextColor;

void scroll();
void move_csr();
void clear();
void write_char(char c);
void write(str s);
void set_text_color(VGATextColor fg, VGATextColor bg);
void init_vga();

#endif // _VGA_H
