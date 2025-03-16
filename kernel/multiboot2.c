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

multiboot2_info_t *parse_multiboot2(u32 addr) {
    multiboot2_info_t *mbi = (multiboot2_info_t *)addr;

    multiboot2_tag_t *tag = (multiboot2_tag_t *)(addr + 8);
    while (tag->type != 0) {
        tag = (multiboot2_tag_t *)((u32)tag + ((tag->size + 7) & ~7));
    }

    return mbi;
}
