/*
 framebuffer.h
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: Framebuffer helper functions
 Copyright (c) 2025 Maxims Enterprise
*/

#ifndef _FRAMEBUFFER_H
#define _FRAMEBUFFER_H

#include "common.h"

typedef struct {
    void *framebuffer;
    u32 width;
    u32 height;
    u32 pitch;
    u32 bpp;
} framebuffer_info_t;

framebuffer_info_t get_framebuffer_info(u32 *mb_info);
void draw_square(framebuffer_info_t *framebuffer, u32 x, u32 y, u32 width,
                 u32 height, u32 color);

#endif // _FRAMEBUFFER_H
