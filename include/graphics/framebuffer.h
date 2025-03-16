/*
 framebuffer.h
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: Framebuffer extraction and drawing utilities
 Copyright (c) 2025 Maxims Enterprise
*/

#ifndef _FRAMEBUFFER_H
#define _FRAMEBUFFER_H

#include "common.h"
#include "multiboot2.h"

typedef struct multiboot2_tag_framebuffer {
    u32 type;
    u32 size;
    u64 framebuffer_addr;
    u32 framebuffer_pitch;
    u32 framebuffer_width;
    u32 framebuffer_height;
    u8 framebuffer_bpp;
    u8 framebuffer_type;
    u16 reserved;
} __attribute__((packed)) multiboot2_tag_framebuffer_t;

typedef struct framebuffer_info {
    u8 *addr;
    u32 width;
    u32 height;
    u32 pitch;
    u8 bpp;
} framebuffer_info_t;

framebuffer_info_t *get_framebuffer_info(multiboot2_info_t *mbi);
void draw_red_line(framebuffer_info_t *fb);

#endif // _FRAMEBUFFER_H
