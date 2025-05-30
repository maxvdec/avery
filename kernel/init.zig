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
const framebuffer = @import("framebuffer");
const font = @import("font");
const terminal = @import("terminal");
const pit = @import("pit");
const syscall = @import("syscall");

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

const STACK_SIZE: usize = 16384; // 16 KiB

export fn kernel_main(magic: u32, addr: u32) noreturn {
    @setRuntimeSafety(false);
    out.initOutputs();
    out.switchToSerial();

    if (magic != MULTIBOOT2_HEADER_MAGIC) {
        out.printHex(magic);
        sys.panic("Bootloader mismatch. Try using Multiboot2 or reconfigure your bootloader.");
    }
    gdt.init();
    idt.init();
    isr.init();
    asm volatile ("sti");
    irq.init();
    pit.init();
    syscall.initSyscall();
    out.println("All core services initialized.");

    const bootInfo = multiboot2.getBootInfo(addr);
    const memMap = multiboot2.getMemoryMapTag(bootInfo);
    if (memMap.isPresent() == false) {
        sys.panic("No memory map found.");
    }

    memoryMap = memMap.unwrap().*;

    const fbPtr = multiboot2.getFramebufferTag(bootInfo);
    if (fbPtr.isPresent() == false) {
        sys.panic("No framebuffer found.");
    }

    const fbTag = fbPtr.unwrap().*;

    physmem.init(memMap.unwrap(), getKernelEnd());
    out.println("Physical memory initialized.");
    virtmem.init();
    out.println("Virtual memory initialized.");
    _ = alloc.initHeap();

    const fb = framebuffer.Framebuffer.init(fbTag);
    const fnt = font.Font.init();
    var fbTerminal = terminal.FramebufferTerminal.init(&fb, &fnt);
    out.println("Graphics initialized.");

    out.switchToGraphics(fbTerminal);
    out.println("The Avery Kernel");
    out.println("Created by Max Van den Eynde");
    out.println("Pre-Alpha Version: paph-0.02\n");
    _ = syscall.perform(10, 0, 0, 0, 0, 0);

    fusion.main(getMemoryMap());
    while (true) {
        fbTerminal.updateCursor();
        sys.delay(16);
    }
}
