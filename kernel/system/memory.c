/*
 memory.c
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: Memory function implementation
 Copyright (c) 2025 Maxims Enterprise
*/

#include "system/memory.h"
#include "common.h"
#include "vga.h"

void init_pmm(u32 *mb_info) {
    multiboot_tag *tag = (multiboot_tag *)(mb_info + 8);

    while (tag->type != 0) {
        if (tag->type == 6) {
            struct {
                u32 type;
                u32 size;
                u32 entry_size;
                u32 entry_version;
                multiboot_mmap_entry entries[];
            } *mmap = (void *)tag;

            write("Memory Map:\n");

            multiboot_mmap_entry *entry = mmap->entries;
            u32 mmap_end = (u32)tag + tag->size;

            while ((u32)entry < mmap_end) {
                u64 base = entry->addr;
                u64 length = entry->len;
                u32 type = entry->type;

                write("Base: ");
                write_hex(base);
                write(" Length: ");
                write_hex(length);
                write(" Type: ");
                write_hex(type);
                write("\n");

                entry = (multiboot_mmap_entry *)((u32)entry + mmap->entry_size);
            }
        }

        tag = (multiboot_tag *)((u8 *)tag + ((tag->size + 7) & ~7));
    }
}

u32 page_directory[1024] __attribute__((aligned(4096)));

void init_paging() {
    u32 num_entries = KERNEL_MEMORY_LIMIT_MB / 4;

    for (u32 i = 0; i < num_entries; i++) {
        page_directory[i] =
            (i * 0x400000) | PAGE_PRESENT | PAGE_WRITABLE | PAGE_SIZE_4MB;
    }

    for (u32 i = num_entries; i < 1024; i++) {
        page_directory[i] = 0;
    }

    asm volatile("mov %0, %%cr3" ::"r"(page_directory));

    u32 cr4;
    asm volatile("mov %%cr4, %0" : "=r"(cr4));
    cr4 |= (1 << 4);
    asm volatile("mov %0, %%cr4" ::"r"(cr4));

    u32 cr0;
    asm volatile("mov %%cr0, %0" : "=r"(cr0));
    cr0 |= (1 << 31);
    asm volatile("mov %0, %%cr0" ::"r"(cr0));
}

void *pmm_alloc() {
    for (size i = 0; i < MAX_FRAMES / 32; i++) {
        if (memory_bitmap[i] != 0xFFFFFFFF) {
            for (size j = 0; j < 32; j++) {
                if (!(memory_bitmap[i] & (1 << j))) {
                    memory_bitmap[i] |= (1 << j);
                    return (void *)((i * 32 + j) * PAGE_SIZE);
                }
            }
        }
    }
    return NULL;
}

void pmm_free(void *ptr) {
    u32 frame = (u32)ptr / PAGE_SIZE;
    clear_frame(frame);
}

void init_vmm() {
    for (int i = 0; i < 1024; i++) {
        page_directory[i] = 0;
    }

    u32 num_entries =
        (KERNEL_MEMORY_LIMIT_MB * 1024 * 1024) / 0x400000; // 4MB pages

    for (u32 i = 0; i < num_entries; i++) {
        page_directory[i] =
            (i * 0x400000) | PAGE_PRESENT | PAGE_WRITABLE | PAGE_SIZE_4MB;
    }

    asm volatile("mov %0, %%cr3" ::"r"(page_directory));

    u32 cr4;
    asm volatile("mov %%cr4, %0" : "=r"(cr4));
    cr4 |= (1 << 4);
    asm volatile("mov %0, %%cr4" ::"r"(cr4));

    u32 cr0;
    asm volatile("mov %%cr0, %0" : "=r"(cr0));
    cr0 |= 0x80000000;
    asm volatile("mov %0, %%cr0" ::"r"(cr0));
}

void vmm_map_mage(void *phys_addr, void *virt_addr) {
    u32 pd_index = (u32)virt_addr >> 22;
    u32 pt_index = ((u32)virt_addr >> 12) & 0x3FF;

    if (!(page_directory[pd_index] & PAGE_PRESENT)) {
        page_directory[pd_index] =
            (u32)pmm_alloc() | PAGE_PRESENT | PAGE_WRITABLE;
    }

    u32 *page_table = (u32 *)(page_directory[pd_index] & ~0xFFF);
    page_table[pt_index] = (u32)phys_addr | PAGE_PRESENT | PAGE_WRITABLE;
}

void vmm_unmap_page(void *virt_addr) {
    u32 pd_index = (u32)virt_addr >> 22;
    u32 pt_index = ((u32)virt_addr >> 12) & 0x3FF;

    if (page_directory[pd_index] & PAGE_PRESENT) {
        u32 *page_table = (u32 *)(page_directory[pd_index] & ~0xFFF);
        page_table[pt_index] = 0;
    }
}

void *malloc(size size) {
    if ((u32)heap_top + size > HEAP_END) {
        return NULL;
    }

    if (size % 8 != 0) {
        size += 8 - (size % 8);
    }

    void *allocated = heap_top;
    heap_top += size;

    return allocated;
}

void free(void *ptr) {
    if (!ptr)
        return;

    u32 addr = (u32)ptr;
    u32 frame = addr / PAGE_SIZE;

    clear_frame(frame);

    asm volatile("invlpg (%0)" ::"r"(addr) : "memory");
}
