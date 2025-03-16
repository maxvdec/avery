/*
 framebuffer.c
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: Framebuffer function implementatio
 Copyright (c) 2025 Maxims Enterprise
*/

#include "graphics/framebuffer.h"
#include "common.h"
#include "multiboot2.h"
#include "system/memory.h"
#include "vga.h"

framebuffer_info_t *get_framebuffer_info(multiboot2_info_t *mbi) {
    static framebuffer_info_t fb_info;
    multiboot2_tag_t *tag = (multiboot2_tag_t *)((uintptr_t)mbi + 8);

    while (tag->type != 0) {
        if (tag->type == 0x8) {
            multiboot2_tag_framebuffer_t *fb_tag =
                (multiboot2_tag_framebuffer_t *)tag;

            fb_info.addr = (u8 *)(uintptr_t)fb_tag->framebuffer_addr;
            fb_info.width = fb_tag->framebuffer_width;
            fb_info.height = fb_tag->framebuffer_height;
            fb_info.pitch = fb_tag->framebuffer_pitch;
            fb_info.bpp = fb_tag->framebuffer_bpp;

            return &fb_info;
        }

        tag = (multiboot2_tag_t *)((uintptr_t)tag + ((tag->size + 7) & ~7));
    }

    write("No framebuffer found\n");
    return NULL;
}

void draw_red_line(framebuffer_info_t *fb) {
    if (!fb->addr) {
        return;
    }

    write_hex((uintptr_t)fb->addr);
    write("\n");
    write_hex(fb->width);
    write("\n");
    write_hex(fb->height);
    write("\n");
    write_hex(fb->pitch);
    write("\n");
    write_hex(fb->bpp);
    write("\n");

    uintptr_t fb_addr = (uintptr_t)fb->addr;

    u32 line_y = fb->height / 2;

    for (u32 x = 0; x < fb->width; x++) {
        u32 pixel_offset = (line_y * fb->pitch) + (x * (fb->bpp / 8));

        if (pixel_offset >= fb->pitch * fb->height) {
            write("Pixel offset out of bounds!\n");
            return;
        }

        if (fb->bpp == 32) {
            *(uintptr_t *)(fb_addr + pixel_offset) = 0x00FF0000;
        } else if (fb->bpp == 24) {
            *(u8 *)(fb_addr + pixel_offset) = 0xFF;
            *(u8 *)(fb_addr + pixel_offset + 1) = 0x00;
            *(u8 *)(fb_addr + pixel_offset + 2) = 0x00;
        }
    }
}
