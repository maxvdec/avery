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

const MULTIBOOT2_HEADER_MAGIC: u32 = 0x36d76289;

extern var kernel_end: u8;
inline fn getKernelEnd() usize {
    return @intFromPtr(&kernel_end);
}

export fn kernel_main(magic: u32, addr: u32) noreturn {
    @setRuntimeSafety(false);
    out.initOutputs();
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

    out.print("Memory map found at: ");
    out.printHex(@intFromPtr(memMap.first()));
    out.print("\n");
    out.print("Kernel end at: ");
    out.printHex(getKernelEnd());
    out.print("\n");
    out.print("Memory map size: ");
    out.printHex(memMap.first().size);
    out.print("\n");

    physmem.init(memMap.first(), getKernelEnd());
    const page = physmem.allocPage();
    if (page == null) {
        sys.panic("No free pages available.");
    }
    out.print("Allocated page at: ");
    out.printHex(page.?);
    out.print("\n");

    //out.clear();
    out.println("The Avery Kernel");
    out.println("Created by Max Van den Eynde");
    out.println("Pre-Alpha Version: paph-0.01");

    while (true) {}
}
