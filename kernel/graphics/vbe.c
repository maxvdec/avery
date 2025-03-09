/*
 vbe.c
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: VBE function implementation
 Copyright (c) 2025 Maxims Enterprise
*/

#include "graphics/vbe.h"

void put_pixel(u32 x, u32 y, u32 color, vbe_mode_info_t *vbe) {
    if (!vbe || x >= vbe->width || y >= vbe->height)
        return; // Avoid out-of-bounds

    u32 *fb = (u32 *)vbe->framebuffer;
    u32 pitch = vbe->pitch / 4; // Convert bytes to pixels

    fb[y * pitch + x] = color;
}
