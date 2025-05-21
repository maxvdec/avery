const str = @import("string");
const out = @import("output");
const gdt = @import("gdt");
const idt = @import("idt");
const sys = @import("system");
const isr = @import("isr");
const irq = @import("irq");
const time = @import("time");
const keyboard = @import("keyboard");
const in = @import("input");
const multiboot2 = @import("multiboot2");
const physmem = @import("physical_mem");
const virtmem = @import("virtual_mem");
const tests = @import("boot_tests");
const alloc = @import("allocator");
const mem = @import("memory");
const fusion = @import("fusion");
const ata = @import("ata");
const fat32 = @import("fat32");
const framebuffer = @import("framebuffer");

const MULTIBOOT2_HEADER_MAGIC: u32 = 0x36d76289;

extern var kernel_end: u8;
inline fn getKernelEnd() usize {
    return @intFromPtr(&kernel_end);
}

extern var kernel_start: u8;
inline fn getKernelStart() usize {
    return @intFromPtr(&kernel_start);
}

var memoryMap: multiboot2.MemoryMapTag = undefined;
pub fn getMemoryMap() multiboot2.MemoryMapTag {
    return memoryMap;
}

export fn kernel_main(magic: u32, addr: u32) noreturn {
    @setRuntimeSafety(false);
    out.initOutputs();
    out.clear();
    if (magic != MULTIBOOT2_HEADER_MAGIC) {
        sys.panic("Bootloader mismatch. Try using Multiboot2 or reconfigure your bootloader.");
    }
    gdt.init();
    idt.init();
    isr.init();
    asm volatile ("sti");
    irq.init();

    const bootInfo = multiboot2.getBootInfo(addr);
    const memMap = multiboot2.getMemoryMapTag(bootInfo);
    if (memMap.second() == false) {
        sys.panic("No memory map found.");
    }

    memoryMap = memMap.first().*;

    const framebufferTag = multiboot2.getFramebufferTag(bootInfo);
    if (framebufferTag.second() == false) {
        sys.panic("No framebuffer found.");
    }

    physmem.init(memMap.first(), getKernelEnd());
    virtmem.init();

    framebuffer.switchToTextMode();

    out.println("The Avery Kernel");
    out.println("Created by Max Van den Eynde");
    out.println("Pre-Alpha Version: paph-0.01\n");
    fusion.main(getMemoryMap());

    while (true) {}
}
