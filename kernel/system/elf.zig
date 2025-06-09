const vmm = @import("virtual_mem");
const pmm = @import("physical_mem");
const out = @import("output");
const sys = @import("system");
const mem = @import("memory");
const alloc = @import("allocator");
const kalloc = @import("kern_allocator");
const ext = @import("extensions");
const proc = @import("process");

const ELF_MAGIC = [4]u8{ 0x7F, 'E', 'L', 'F' };

const ELF_CLASS_32 = 1;
const ELF_DATA_LSB = 1;
const ELF_VERSION_CURRENT = 1;

const ET_EXEC = 2;
const EM_386 = 3;

const PT_NULL = 0;
const PT_LOAD = 1;
const PT_DYNAMIC = 2;
const PT_INTERP = 3;

const PF_X = 1 << 0;
const PF_W = 1 << 1;
const PF_R = 1 << 2;

const ElfHeader = packed struct {
    ei_mag0: u8,
    ei_mag1: u8,
    ei_mag2: u8,
    ei_mag3: u8,
    ei_class: u8,
    ei_data: u8,
    ei_version: u8,
    ei_osabi: u8,
    ei_abiversion: u8,
    ei_pad0: u8,
    ei_pad1: u8,
    ei_pad2: u8,
    ei_pad3: u8,
    ei_pad4: u8,
    ei_pad5: u8,
    ei_pad6: u8,
    e_type: u16,
    e_machine: u16,
    e_version: u32,
    e_entry: u32,
    e_phoff: u32,
    e_shoff: u32,
    e_flags: u32,
    e_ehsize: u16,
    e_phentsize: u16,
    e_phnum: u16,
    e_shentsize: u16,
    e_shnum: u16,
    e_shstrndx: u16,
};

const ProgramHeader = packed struct {
    p_type: u32,
    p_offset: u32,
    p_vaddr: u32,
    p_paddr: u32,
    p_filesz: u32,
    p_memsz: u32,
    p_flags: u32,
    p_align: u32,
};

extern fn memcpy(
    dest: [*]u8,
    src: [*]const u8,
    len: usize,
) [*]u8;

extern fn memset(
    dest: [*]u8,
    value: u8,
    len: usize,
) [*]u8;

pub fn validateElfHeader(elf_data: []const u8) ?*const ElfHeader {
    @setRuntimeSafety(false);
    if (elf_data.len < @sizeOf(ElfHeader)) {
        return null;
    }

    const header = @as(*const ElfHeader, @alignCast(@ptrCast(elf_data.ptr)));

    if (header.ei_mag0 != ELF_MAGIC[0] or
        header.ei_mag1 != ELF_MAGIC[1] or
        header.ei_mag2 != ELF_MAGIC[2] or
        header.ei_mag3 != ELF_MAGIC[3])
    {
        return null;
    }

    if (header.ei_class != ELF_CLASS_32) {
        return null;
    }

    if (header.ei_data != ELF_DATA_LSB) {
        return null;
    }

    if (header.e_version != ELF_VERSION_CURRENT) {
        return null;
    }

    if (header.e_type != ET_EXEC) {
        return null;
    }

    if (header.e_machine != EM_386) {
        return null;
    }

    return header;
}

pub const ExtractedElf = struct {
    entry_offset: u32,
    code: []const u8,
};

pub fn extractCode(elf_data: []const u8) ?ExtractedElf {
    @setRuntimeSafety(false);
    const header = validateElfHeader(elf_data) orelse {
        out.println("Invalid ELF header");
        return null;
    };

    out.println("Valid ELF header found");
    out.print("ELF entry point: ");
    out.printHex(header.e_entry);
    out.println("");
    out.print("ELF program header number: ");
    out.printHex(header.e_phnum);
    out.println("");

    const ph_offset = header.e_phoff;
    var load_segment: ?*const ProgramHeader = null;
    var min_vaddr: u32 = 0xFFFFFFFF;

    for (0..header.e_phnum) |i| {
        const ph_addr = ph_offset + (i * header.e_phentsize);
        if (ph_addr + @sizeOf(ProgramHeader) > elf_data.len) {
            out.println("Program header out of bounds");
            return null;
        }

        const ph = @as(*const ProgramHeader, @alignCast(@ptrCast(elf_data.ptr + ph_addr)));

        if (ph.p_type == PT_LOAD) {
            if (ph.p_vaddr < min_vaddr) {
                min_vaddr = ph.p_vaddr;
                load_segment = ph;
            }
        }
    }

    const segment = load_segment orelse {
        out.println("No load segment found");
        return null;
    };

    out.print("Found load segment at offset: ");
    out.printHex(segment.p_vaddr);
    out.println("");
    out.print("File size: ");
    out.printHex(segment.p_filesz);
    out.println("");

    if (segment.p_offset + segment.p_filesz > elf_data.len) {
        out.println("Load segment file size exceeds ELF data length");
        return null;
    }

    const code = elf_data[segment.p_offset .. segment.p_offset + segment.p_filesz];
    const entry_offset = header.e_entry - segment.p_vaddr;

    return .{
        .entry_offset = entry_offset,
        .code = code,
    };
}

pub fn loadElfProcess(elf_data: []const u8) ?*proc.Process {
    @setRuntimeSafety(false);
    const elf_info = extractCode(elf_data) orelse {
        out.println("Failed to extract code from ELF");
        return null;
    };

    const process = proc.Process.createProcess(elf_info.code) orelse {
        out.println("Failed to create process from ELF code");
        return null;
    };

    process.context.eip = vmm.USER_CODE_VADDR + elf_info.entry_offset;

    return process;
}

pub fn elfTest() void {
    out.println("Testing ELF loader...");

    const elf_bytes = [_]u8{
        0x7F, 'E', 'L', 'F', // e_ident[0..3] - ELF magic
        0x01, // e_ident[4] - EI_CLASS (32-bit)
        0x01, // e_ident[5] - EI_DATA (little endian)
        0x01, // e_ident[6] - EI_VERSION
        0x00, // e_ident[7] - EI_OSABI
        0x00, 0x00, 0x00, 0x00, // e_ident[8..11] - padding
        0x00, 0x00, 0x00, 0x00, // e_ident[12..15] - padding
        0x02, 0x00, // e_type - ET_EXEC
        0x03, 0x00, // e_machine - EM_386
        0x01, 0x00, 0x00, 0x00, // e_version
        0x00, 0x10, 0x40, 0x00, // e_entry - 0x401000
        0x34, 0x00, 0x00, 0x00, // e_phoff - program header offset
        0x00, 0x00, 0x00, 0x00, // e_shoff - section header offset
        0x00, 0x00, 0x00, 0x00, // e_flags
        0x34, 0x00, // e_ehsize - ELF header size
        0x20, 0x00, // e_phentsize - program header size
        0x01, 0x00, // e_phnum - number of program headers
        0x00, 0x00, // e_shentsize
        0x00, 0x00, // e_shnum
        0x00, 0x00, // e_shstrndx
        0x01, 0x00, 0x00, 0x00, // p_type - PT_LOAD
        0x54, 0x00, 0x00, 0x00, // p_offset - offset in file
        0x00, 0x10, 0x40, 0x00, // p_vaddr - virtual address
        0x00, 0x10, 0x40, 0x00, // p_paddr - physical address
        0x02, 0x00, 0x00, 0x00, // p_filesz - size in file
        0x02, 0x00, 0x00, 0x00, // p_memsz - size in memory
        0x05, 0x00, 0x00, 0x00, // p_flags - PF_R | PF_X
        0x00, 0x10, 0x00, 0x00, // p_align - alignment
        0xEB, 0xFE, // jmp $ (infinite loop)
    };

    const process = loadElfProcess(&elf_bytes) orelse {
        out.println("Failed to load ELF process");
        return;
    };

    process.run();
}
