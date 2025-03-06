
#include "common.h"
#include "console.h"
#include "disk/ata.h"
#include "disk/fat32.h"
#include "drivers/timer.h"
#include "system/gdt.h"
#include "system/idt.h"
#include "system/irq.h"
#include "system/isr.h"
#include "system/memory.h"
#include "vga.h"

#define MULTIBOOT_HEADER_MAGIC 0x2BADB002

void kernel_main(u32 magic, u32 *info) {
    // Initialize all systems
    init_vga();
    init_gdt();
    init_idt();
    init_isrs();
    init_irqs();

    if (magic != MULTIBOOT_HEADER_MAGIC) {
        write("Invalid magic number\n");
        write_hex(magic);
        write("\n");
        write_hex(*info);
        return;
    }

    init_timer();
    init_pmm((multiboot_info *)info);
    init_paging();
    init_vmm();
    fat32_read_mbr();
    fat32_read_boot_sector();

    write("Avery Kernel\n");
    write("Development Version\n");
    write("Created by Maxims Enterprise in 2025\n\n");
    while (true) {
        init_console();
    }
}
