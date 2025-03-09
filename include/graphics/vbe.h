/*
 vbe.h
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: VBE Information structure
 Copyright (c) 2025 Maxims Enterprise
*/

#ifndef _VBE_H
#define _VBE_H

#include "common.h"

typedef struct {
    u16 attributes;
    u8 winA, winB;
    u16 granularity;
    u16 winsize;
    u16 segmentA, segmentB;
    u32 real_fct_ptr;
    u16 pitch;
    u16 width, height;
    u8 w_char, y_char, planes, bpp, banks;
    u8 memory_model, bank_size, image_pages;
    u8 reserved0;
    u8 red_mask, red_position;
    u8 green_mask, green_position;
    u8 blue_mask, blue_position;
    u8 reserved_mask, reserved_position;
    u8 directcolor_attributes;
    u32 framebuffer;
    u32 off_screen_mem_off;
    u16 off_screen_mem_size;
    u8 reserved1[206];
} __attribute__((packed)) vbe_mode_info_t;

void put_pixel(u32 x, u32 y, u32 color, vbe_mode_info_t *vbe_info);

#endif // _VBE_H
