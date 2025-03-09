/*
 multiboot2.c
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: Multiboot2 specification function
 Copyright (c) 2025 Maxims Enterprise
*/

#include "multiboot2.h"
#include "common.h"
#include "vga.h"

multiboot2_info_t *parse_multiboot2(u32 addr) {
    multiboot2_info_t *info = (multiboot2_info_t *)addr;

    if (info->total_size < sizeof(multiboot2_info_t)) {
        write("Invalid Multiboot2 header size\n");
        return NULL;
    }

    write("Multiboot2 Header:\n");
    write("Total size: ");
    write_hex(info->total_size);
    write("\n");
    write("Tags Address: ");
    write_hex(info->tags);
    write("\n");

    u32 tag_addr = info->tags;
    while (tag_addr < addr + info->total_size) {
        multiboot2_tag_t *tag = (multiboot2_tag_t *)tag_addr;

        write("Tag Type: ");
        write_hex(tag->type);
        write(", Tag Size: ");
        write_hex(tag->size);
        write("\n");

        tag_addr += tag->size;
    }

    return info;
}
