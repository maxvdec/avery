/*
 memory.h
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: Memory function splitted to support different types of memory
 Copyright (c) 2025 Maxims Enterprise
*/

#ifndef _MEMORY_H
#define _MEMORY_H

#include "common.h"

// === Physical Memory Management ===
typedef struct multiboot_mmap_entry {
    u32 size;
    u64 addr;
    u64 len;
    u32 type;
} __attribute__((packed)) multiboot_mmap_entry;

typedef struct multiboot_tag {
    u32 type;
    u32 size;
} __attribute__((packed)) multiboot_tag;

#define PAGE_SIZE 4096
#define MEMORY_SIZE_MB 128
#define MAX_FRAMES (MEMORY_SIZE_MB * 1024 * 1024 / PAGE_SIZE)
#define BITMAP_SIZE (MAX_FRAMES / 32)

static u32 memory_bitmap[BITMAP_SIZE] = {0};

void init_pmm(u32 *mbi);
void *pmm_alloc();
void pmm_free(void *ptr);

static inline void set_frame(u32 frame) {
    memory_bitmap[frame / 32] |= (1 << (frame % 32));
};

static inline void clear_frame(u32 frame) {
    memory_bitmap[frame / 32] &= ~(1 << (frame % 32));
};

// === Paging ===
#define PAGE_PRESENT 0x1
#define PAGE_WRITABLE 0x2
#define PAGE_SIZE_4MB 0x80

#define KERNEL_MEMORY_LIMIT_MB 64

extern u32 page_directory[1024] __attribute__((aligned(4096)));

void init_paging();

// === Virtual Memory Management ===

void init_vmm();
void vmm_map_mage(void *phys_addr, void *virt_addr);
void vmm_unmap_page(void *virt_addr);

// === Heap ===

#define HEAP_START 0x100000
#define HEAP_SIZE 0x100000
#define HEAP_END (HEAP_START + HEAP_SIZE)

static void *heap_top = (void *)HEAP_START;

#endif // _MEMORY_H
