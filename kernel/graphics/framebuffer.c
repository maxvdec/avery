/*
 framebuffer.c
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: Framebuffer code for initialitzation
 Copyright (c) 2025 Maxims Enterprise
*/

#include "graphics/framebuffer.h"

framebuffer_info_t get_framebuffer_info(u32 *mb_info) {
    framebuffer_info_t info = {0};

    if (!mb_info) {
        return info;
    }

    if (mb_info[0] & 0x100) {
        if (mb_info[16] != 0) {
            info.framebuffer = (void *)mb_info[16];
            info.width = mb_info[17];
            info.height = mb_info[18];
            info.pitch = mb_info[19];
            info.bpp = mb_info[20];

            if (info.width == 0 || info.height == 0 || info.pitch == 0 ||
                info.bpp == 0) {
                return (framebuffer_info_t){0};
            }
        }
    }

    return info;
}

void draw_square(framebuffer_info_t *framebuffer, u32 x, u32 y, u32 width,
                 u32 height, u32 color) {
    if (framebuffer->framebuffer == 0) {
        return;
    }
    u32 *fb = (u32 *)framebuffer->framebuffer;
    for (u32 i = 0; i < height; i++) {
        for (u32 j = 0; j < width; j++) {
            fb[(y + i) * framebuffer->width + x + j] = color;
        }
    }
}
