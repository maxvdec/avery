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
const vfs = @import("vfs");
const tss = @import("tss");
const process = @import("process");

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

extern fn memcpy(
    dest: [*]u8,
    src: [*]const u8,
    len: usize,
) [*]u8;

const STACK_SIZE: usize = 16384; // 16 KiB

export fn kernel_main(magic: u32, addr: u32) noreturn {
    @setRuntimeSafety(false);
    out.initOutputs();
    out.switchToSerial();

    // Sanity checks
    if (magic != MULTIBOOT2_HEADER_MAGIC) {
        out.printHex(magic);
        sys.panic("Bootloader mismatch. Try using Multiboot2 or reconfigure your bootloader.");
    }

    // Initialize core services
    gdt.init();
    tss.init();
    gdt.gdt_flush();
    tss.loadTss();
    idt.init();
    isr.init();
    asm volatile ("sti");
    irq.init();
    pit.init();
    syscall.initSyscall();
    out.println("All core services initialized.");

    // Setup memory management
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

    // Get some utilities for the kernel
    _ = alloc.initHeap();
    _ = fusion.getAtaController();

    // Obtain the framebuffer and font
    const fb = framebuffer.Framebuffer.init(fbTag);
    const fnt = font.Font.init();
    var fbTerminal = terminal.FramebufferTerminal.init(&fb, &fnt);

    const hello_world_program = [_]u8{
        // write(1, current_addr + 20, 14)
        0xB8, 0x01, 0x00, 0x00, 0x00, // mov eax, 1         ; syscall: write
        0xBB, 0x01, 0x00, 0x00, 0x00, // mov ebx, 1         ; fd: stdout
        0xB9, 0x14, 0x00, 0x40, 0x00, // mov ecx, USER_SPACE_START + 20  ; message address
        0xBA, 0x0E, 0x00, 0x00, 0x00, // mov edx, 14        ; length
        0xCD, 0x80, // int 0x80           ; invoke syscall
        0xEB, 0xFE, // jmp $              ; infinite loop
        // Message at offset 20
        'H',  'e',
        'l',  'l',
        'o',  ',',
        ' ',  'W',
        'o',  'r',
        'l',  'd',
        '!',  '\n',
    };

    // Initialize the terminal
    out.switchToGraphics(&fbTerminal);

    const proc = process.Process.create(&hello_world_program) orelse {
        out.println("Failed to create process for hello world program.");
        sys.panic("Process creation failed.");
    };
    proc.switchTo();

    out.println("The Avery Kernel");
    out.println("Created by Max Van den Eynde");
    out.println("Pre-Alpha Version: paph-0.02\n");

    fusion.main(getMemoryMap());
    while (true) {
        fbTerminal.updateCursor();
        sys.delay(16);
    }
}

// These functions are used by the syscall handler to print messages to the terminal.
// They are sort of the services that the kernel provides to user programs.
export fn kern_print(string: [*]const u8, len: usize) void {
    out.println(string[0..len]);
}

export fn kern_writePath(buf: [*]const u8, len: usize, directory: [*]const u8, directoryLen: usize, partitionNumber: u32) u32 {
    if (!vfs.fileExists(&fusion.getAtaController().master, directory[0..directoryLen], partitionNumber)) {
        const result = vfs.createFile(&fusion.getAtaController().master, directory[0..directoryLen], partitionNumber);
        if (result == null) {
            return 1; // Failed to create file
        }
    }

    const fileContents = vfs.readFile(&fusion.getAtaController().master, @intCast(partitionNumber), buf[0..len]);
    if (fileContents == null) {
        return 2; // Failed to read file
    }
    const joinedText = mem.joinBytes(u8, fileContents.?, buf[0..len]);
    const result = vfs.writeToFile(&fusion.getAtaController().master, directory[0..directoryLen], joinedText, partitionNumber);
    if (result == null) {
        return 3; // Failed to write to file
    }
    return 0;
}

export fn kern_read(buf: [*]u8, len: usize, directory: [*]const u8, directoryLen: usize, partitionNumber: u32) u32 {
    const fileContents = vfs.readFile(&fusion.getAtaController().master, @intCast(partitionNumber), directory[0..directoryLen]);
    if (fileContents == null) {
        return 1; // Failed to read file
    }
    const bytesToCopy = @min(len, fileContents.?.len);
    _ = memcpy(buf, fileContents.?.ptr, bytesToCopy);
    return bytesToCopy;
}

export fn kern_readStdin(buf: [*]u8, len: usize) u32 {
    const input = in.readbytes(len);
    const bytesToCopy = @min(len, input.len);
    _ = memcpy(buf, input.ptr, bytesToCopy);
    return bytesToCopy;
}
