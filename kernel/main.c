
#include "common.h"
#include "console.h"
#include "disk/fat32.h"
#include "drivers/timer.h"
#include "graphics/framebuffer.h"
#include "multiboot2.h"
#include "system/gdt.h"
#include "system/idt.h"
#include "system/irq.h"
#include "system/isr.h"
#include "system/memory.h"
#include "vga.h"

#define MULTIBOOT2_HEADER_MAGIC 0x36d76289

void kernel_main(u32 magic, u32 addr) {
    // Initialize all systems
    init_vga();
    init_gdt();
    init_idt();
    init_isrs();
    init_irqs();
    if (magic != MULTIBOOT2_HEADER_MAGIC) {
        boot_panic("No multiboot information provided");
        return;
    }

    init_timer();

    multiboot2_info_t *mbi = parse_multiboot2(addr);
    init_pmm(mbi);
    init_paging();
    init_vmm();
    fat32_read_mbr();
    fat32_read_boot_sector();

    framebuffer_info_t *fb_info = get_framebuffer_info(mbi);
    if (!fb_info || !fb_info->addr) {
        boot_panic("No framebuffer found");
        return;
    }

    write("Avery Kernel\n");
    write("Development Version\n");
    write("Created by Maxims Enterprise in 2025\n\n");
    while (true) {
        init_console();
    }
}
