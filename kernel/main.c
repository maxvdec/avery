
#include "common.h"
#include "console.h"
#include "disk/ata.h"
#include "disk/fat32.h"
#include "drivers/timer.h"
#include "graphics/framebuffer.h"
#include "system/gdt.h"
#include "system/idt.h"
#include "system/irq.h"
#include "system/isr.h"
#include "system/memory.h"
#include "vga.h"

#define MULTIBOOT2_HEADER_MAGIC 0xE85250D6

void kernel_main(u32 *mb_info) {
    // Initialize all systems
    init_vga();
    init_gdt();
    init_idt();
    init_isrs();
    init_irqs();
    if (!mb_info) {
        write("No multiboot information provided\n");
        return;
    }

    init_timer();
    init_pmm(mb_info);
    init_paging();
    init_vmm();
    fat32_read_mbr();
    fat32_read_boot_sector();

    framebuffer_info_t fb_info = get_framebuffer_info(mb_info);
    if (fb_info.framebuffer) {
        draw_square(&fb_info, 0, 0, 100, 100, 0xFF0000);
    }

    write("Avery Kernel\n");
    write("Development Version\n");
    write("Created by Maxims Enterprise in 2025\n\n");
    while (true) {
        init_console();
    }
}
