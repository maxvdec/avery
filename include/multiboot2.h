/*
 multiboot2.h
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: Mutiboot2 tag parsing and structure
 Copyright (c) 2025 Maxims Enterprise
*/

#ifndef MULTIBOOT2_H
#define MULTIBOOT2_H

#include "common.h"

typedef struct multiboot2_tag {
    u32 type;
    u32 size;
    u8 data[];
} multiboot2_tag_t;

typedef struct multiboot2_info {
    u32 total_size;
    u32 reserved;
    u32 tags;
} multiboot2_info_t;

#define MULTIBOOT2_TAG_TYPE_END 0
#define MULTIBOOT2_TAG_TYPE_CMDLINE 1
#define MULTIBOOT2_TAG_TYPE_BOOTLOADER 2
#define MULTIBOOT2_TAG_TYPE_MODULE 3
#define MULTIBOOT2_TAG_TYPE_BASIC_MEMINFO 4
#define MULTIBOOT2_TAG_TYPE_BOOTDEV 5
#define MULTIBOOT2_TAG_TYPE_MEMORY_MAP 6
#define MULTIBOOT2_TAG_TYPE_FRAMEBUFFER 8
#define MULTIBOOT2_TAG_TYPE_ELF_SECTIONS 9
#define MULTIBOOT2_TAG_TYPE_APM 10
#define MULTIBOOT2_TAG_TYPE_VBE 11

multiboot2_info_t *parse_multiboot2(u32 addr);

#endif // MULTIBOOT2_H
