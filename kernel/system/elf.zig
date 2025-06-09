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

const ET_NONE = 0;
const ET_REL = 1;
const ET_EXEC = 2;
const ET_DYN = 3;
const ET_CORE = 4;

const EM_386 = 3;

const PT_NULL = 0;
const PT_LOAD = 1;
const PT_DYNAMIC = 2;
const PT_INTERP = 3;
const PT_NOTE = 4;
const PT_SHLIB = 5;
const PT_PHDR = 6;
const PT_TLS = 7;

const PF_X = 1 << 0;
const PF_W = 1 << 1;
const PF_R = 1 << 2;

const SHT_NULL = 0;
const SHT_PROGBITS = 1;
const SHT_SYMTAB = 2;
const SHT_STRTAB = 3;
const SHT_RELA = 4;
const SHT_HASH = 5;
const SHT_DYNAMIC = 6;
const SHT_NOTE = 7;
const SHT_NOBITS = 8;
const SHT_REL = 9;
const SHT_SHLIB = 10;
const SHT_DYNSYM = 11;

const SHF_WRITE = 1 << 0;
const SHF_ALLOC = 1 << 1;
const SHF_EXECINSTR = 1 << 2;

const DT_NULL = 0;
const DT_NEEDED = 1;
const DT_PLTRELSZ = 2;
const DT_PLTGOT = 3;
const DT_HASH = 4;
const DT_STRTAB = 5;
const DT_SYMTAB = 6;
const DT_RELA = 7;
const DT_RELASZ = 8;
const DT_RELAENT = 9;
const DT_STRSZ = 10;
const DT_SYMENT = 11;
const DT_INIT = 12;
const DT_FINI = 13;
const DT_SONAME = 14;
const DT_RPATH = 15;
const DT_SYMBOLIC = 16;
const DT_REL = 17;
const DT_RELSZ = 18;
const DT_RELENT = 19;
const DT_PLTREL = 20;
const DT_DEBUG = 21;
const DT_TEXTREL = 22;
const DT_JMPREL = 23;

const R_386_NONE = 0;
const R_386_32 = 1;
const R_386_PC32 = 2;
const R_386_GOT32 = 3;
const R_386_PLT32 = 4;
const R_386_COPY = 5;
const R_386_GLOB_DAT = 6;
const R_386_JMP_SLOT = 7;
const R_386_RELATIVE = 8;

const STB_LOCAL = 0;
const STB_GLOBAL = 1;
const STB_WEAK = 2;

const STT_NOTYPE = 0;
const STT_OBJECT = 1;
const STT_FUNC = 2;
const STT_SECTION = 3;
const STT_FILE = 4;

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

const SectionHeader = packed struct {
    sh_name: u32,
    sh_type: u32,
    sh_flags: u32,
    sh_addr: u32,
    sh_offset: u32,
    sh_size: u32,
    sh_link: u32,
    sh_info: u32,
    sh_addralign: u32,
    sh_entsize: u32,
};

const DynamicEntry = packed struct {
    d_tag: u32,
    d_val: u32, // or d_ptr, same union
};

const Symbol = packed struct {
    st_name: u32,
    st_value: u32,
    st_size: u32,
    st_info: u8,
    st_other: u8,
    st_shndx: u16,
};

const RelEntry = packed struct {
    r_offset: u32,
    r_info: u32,
};

const RelaEntry = packed struct {
    r_offset: u32,
    r_info: u32,
    r_addend: i32,
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

pub const LoadedSection = struct {
    vaddr: u32,
    size: u32,
    flags: u32,
    data: []u8,
};

pub const LoadedLibrary = struct {
    name: []const u8,
    base_addr: u32,
    dynamic_table: []const DynamicEntry,
    symbol_table: ?[]const Symbol,
    string_table: ?[]const u8,
    next: ?*LoadedLibrary,
};

pub const ExtractedElf = struct {
    entry_point: u32,
    sections: []LoadedSection,
    dynamic_table: ?[]const DynamicEntry,
    needed_libraries: [][]const u8,
    is_dynamic: bool,
    base_addr: u32,
};

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

    if (header.e_type != ET_EXEC and header.e_type != ET_DYN) {
        return null;
    }

    if (header.e_machine != EM_386) {
        return null;
    }

    return header;
}

fn getSectionName(elf_data: []const u8, header: *const ElfHeader, section: *const SectionHeader) ?[]const u8 {
    @setRuntimeSafety(false);
    if (header.e_shstrndx == 0) return null;

    const shstrtab_offset = header.e_shoff + (header.e_shstrndx * header.e_shentsize);
    if (shstrtab_offset + @sizeOf(SectionHeader) > elf_data.len) return null;

    const shstrtab = @as(*const SectionHeader, @alignCast(@ptrCast(elf_data.ptr + shstrtab_offset)));
    if (shstrtab.sh_offset + shstrtab.sh_size > elf_data.len) return null;

    const string_table = elf_data[shstrtab.sh_offset .. shstrtab.sh_offset + shstrtab.sh_size];
    if (section.sh_name >= string_table.len) return null;

    const name_start = section.sh_name;
    var name_end = name_start;
    while (name_end < string_table.len and string_table[name_end] != 0) {
        name_end += 1;
    }

    return string_table[name_start..name_end];
}

fn extractNeededLibraries(dynamic_table: []const DynamicEntry, string_table: []const u8) ![][]const u8 {
    var needed_count: usize = 0;

    // Count needed libraries
    for (dynamic_table) |entry| {
        if (entry.d_tag == DT_NEEDED) {
            needed_count += 1;
        }
    }

    if (needed_count == 0) return &[_][]const u8{};

    const needed_libs = alloc.storeMany([]const u8, needed_count);
    var i: usize = 0;

    for (dynamic_table) |entry| {
        if (entry.d_tag == DT_NEEDED) {
            if (entry.d_val < string_table.len) {
                const name_start = entry.d_val;
                var name_end = name_start;
                while (name_end < string_table.len and string_table[name_end] != 0) {
                    name_end += 1;
                }
                needed_libs[i] = string_table[name_start..name_end];
                i += 1;
            }
        }
    }

    return needed_libs[0..i];
}

pub fn extractElfData(elf_data: []const u8) ?ExtractedElf {
    @setRuntimeSafety(false);
    const header = validateElfHeader(elf_data) orelse {
        out.println("Invalid ELF header");
        return null;
    };

    var sections = mem.Array(LoadedSection).init();
    var dynamic_table: ?[]const DynamicEntry = null;
    var base_addr: u32 = 0xFFFFFFFF;
    const is_dynamic = header.e_type == ET_DYN;

    for (0..header.e_phnum - 1) |i| {
        const ph_addr = header.e_phoff + (i * header.e_phentsize);
        if (ph_addr + @sizeOf(ProgramHeader) > elf_data.len) continue;

        const ph = @as(*const ProgramHeader, @alignCast(@ptrCast(elf_data.ptr + ph_addr)));

        if (ph.p_type == PT_LOAD) {
            if (ph.p_vaddr < base_addr) {
                base_addr = ph.p_vaddr;
            }

            if (ph.p_offset + ph.p_filesz > elf_data.len) {
                out.println("Program segment exceeds file bounds");
                continue;
            }

            const section_data = alloc.request(ph.p_memsz) orelse {
                out.println("Failed to allocate memory for section");
                continue;
            };

            if (ph.p_filesz > 0) {
                _ = memcpy(section_data, elf_data.ptr + ph.p_offset, ph.p_filesz);
            }

            if (ph.p_memsz > ph.p_filesz) {
                _ = memset(section_data + ph.p_filesz, 0, ph.p_memsz - ph.p_filesz);
            }

            const section = LoadedSection{
                .vaddr = ph.p_vaddr,
                .size = ph.p_memsz,
                .flags = ph.p_flags,
                .data = section_data[0..ph.p_memsz],
            };

            sections.append(section);
        } else if (ph.p_type == PT_DYNAMIC) {
            if (ph.p_offset + ph.p_filesz <= elf_data.len) {
                const dyn_data = elf_data[ph.p_offset .. ph.p_offset + ph.p_filesz];
                const entry_count = ph.p_filesz / @sizeOf(DynamicEntry);
                dynamic_table = @as([*]const DynamicEntry, @alignCast(@ptrCast(dyn_data.ptr)))[0..entry_count];

                out.print("Found dynamic table with ");
                out.printHex(@intCast(entry_count));
                out.println(" entries");
            }
        }
    }

    var needed_libraries: [][]const u8 = &[_][]const u8{};

    if (dynamic_table) |dyn_table| {
        var string_table: ?[]const u8 = null;
        var strtab_addr: u32 = 0;
        var strtab_size: u32 = 0;

        for (dyn_table) |entry| {
            if (entry.d_tag == DT_STRTAB) {
                strtab_addr = entry.d_val;
            } else if (entry.d_tag == DT_STRSZ) {
                strtab_size = entry.d_val;
            }
        }

        if (strtab_addr != 0 and strtab_size != 0) {
            for (sections.iterate()) |section| {
                if (strtab_addr >= section.vaddr and strtab_addr < section.vaddr + section.size) {
                    const offset = strtab_addr - section.vaddr;
                    if (offset + strtab_size <= section.data.len) {
                        string_table = section.data[offset .. offset + strtab_size];
                        break;
                    }
                }
            }
        }

        if (string_table) |str_table| {
            needed_libraries = extractNeededLibraries(dyn_table, str_table) catch &[_][]const u8{};
        }
    }

    return ExtractedElf{
        .entry_point = header.e_entry,
        .sections = sections.coerce(),
        .dynamic_table = dynamic_table,
        .needed_libraries = needed_libraries,
        .is_dynamic = is_dynamic,
        .base_addr = if (base_addr == 0xFFFFFFFF) 0 else base_addr,
    };
}

fn performRelocations(elf_info: *ExtractedElf, loaded_libs: ?*LoadedLibrary) void {
    @setRuntimeSafety(false);
    const dyn_table = elf_info.dynamic_table orelse return;

    var rel_table: ?[]const RelEntry = null;
    var rel_size: u32 = 0;
    var rela_table: ?[]const RelaEntry = null;
    var rela_size: u32 = 0;

    for (dyn_table) |entry| {
        switch (entry.d_tag) {
            DT_REL => {
                for (elf_info.sections) |section| {
                    if (entry.d_val >= section.vaddr and entry.d_val < section.vaddr + section.size) {
                        const offset = entry.d_val - section.vaddr;
                        rel_table = @as([*]const RelEntry, @alignCast(@ptrCast(section.data.ptr + offset)))[0 .. rel_size / @sizeOf(RelEntry)];
                        break;
                    }
                }
            },
            DT_RELSZ => rel_size = entry.d_val,
            DT_RELA => {
                for (elf_info.sections) |section| {
                    if (entry.d_val >= section.vaddr and entry.d_val < section.vaddr + section.size) {
                        const offset = entry.d_val - section.vaddr;
                        rela_table = @as([*]const RelaEntry, @alignCast(@ptrCast(section.data.ptr + offset)))[0 .. rela_size / @sizeOf(RelaEntry)];
                        break;
                    }
                }
            },
            DT_RELASZ => rela_size = entry.d_val,
            else => {},
        }
    }

    if (rel_table) |rel_entries| {
        for (rel_entries) |rel| {
            processRelocation(elf_info, rel.r_offset, rel.r_info, 0, loaded_libs);
        }
    }

    if (rela_table) |rela_entries| {
        for (rela_entries) |rela| {
            processRelocation(elf_info, rela.r_offset, rela.r_info, rela.r_addend, loaded_libs);
        }
    }
}

fn processRelocation(elf_info: *ExtractedElf, offset: u32, info: u32, addend: i32, loaded_libs: ?*LoadedLibrary) void {
    const rel_type = info & 0xFF;
    const sym_index = info >> 8;

    var target_section: ?*LoadedSection = null;
    for (elf_info.sections) |*section| {
        if (offset >= section.vaddr and offset < section.vaddr + section.size) {
            target_section = section;
            break;
        }
    }

    const section = target_section orelse return;
    const section_offset = offset - section.vaddr;
    if (section_offset + 4 > section.data.len) return;

    const reloc_ptr = @as(*u32, @alignCast(@ptrCast(section.data.ptr + section_offset)));

    switch (rel_type) {
        R_386_NONE => {},
        R_386_32 => {
            const symbol_value = resolveSymbol(elf_info, sym_index, loaded_libs);
            reloc_ptr.* = @intCast(@as(i32, @intCast(symbol_value)) + addend);
        },
        R_386_PC32 => {
            const symbol_value = resolveSymbol(elf_info, sym_index, loaded_libs);
            reloc_ptr.* = @intCast(@as(i32, @intCast(symbol_value)) + addend - @as(i32, @intCast(offset)));
        },
        R_386_RELATIVE => {
            reloc_ptr.* = @intCast(@as(i32, @intCast(elf_info.base_addr)) + addend);
        },
        else => {
            out.print("Unsupported relocation type: ");
            out.printHex(rel_type);
            out.println("");
        },
    }
}

fn resolveSymbol(elf_info: *ExtractedElf, sym_index: u32, loaded_libs: ?*LoadedLibrary) u32 {
    _ = elf_info;
    _ = sym_index;
    _ = loaded_libs;
    // Simplified symbol resolution - in a real implementation,
    // you'd look up the symbol in the symbol table and resolve
    // it against loaded libraries
    return 0;
}

pub fn loadDynamicLibrary(lib_path: []const u8) ?*LoadedLibrary {
    out.print("Loading dynamic library: ");
    out.println(lib_path);
    return null;
}

pub fn loadElfProcess(elf_data: []const u8) ?*proc.Process {
    @setRuntimeSafety(false);
    var elf_info = extractElfData(elf_data) orelse {
        out.println("Failed to extract ELF data");
        return null;
    };

    var loaded_libs: ?*LoadedLibrary = null;
    for (elf_info.needed_libraries) |lib_name| {
        const lib = loadDynamicLibrary(lib_name);
        if (lib) |loaded_lib| {
            loaded_lib.next = loaded_libs;
            loaded_libs = loaded_lib;
        }
    }

    if (elf_info.is_dynamic) {
        performRelocations(&elf_info, loaded_libs);
    }

    var total_size: u32 = 0;
    for (elf_info.sections) |section| {
        const section_end = section.vaddr + section.size - elf_info.base_addr;
        if (section_end > total_size) {
            total_size = section_end;
        }
    }

    const combined_data = alloc.request(total_size) orelse {
        out.println("Failed to allocate combined memory for process");
        return null;
    };
    _ = memset(combined_data, 0, total_size);

    var combined_size: usize = 0;
    for (elf_info.sections) |section| {
        const offset = section.vaddr - elf_info.base_addr;
        if (offset + section.size <= total_size) {
            _ = memcpy(combined_data + offset, section.data.ptr, section.data.len);
            combined_size = @max(combined_size, offset + section.size);
        }
    }

    const process = proc.Process.createProcess(combined_data[0..combined_size]) orelse {
        out.println("Failed to create process from ELF data");
        return null;
    };

    process.context.eip = vmm.USER_CODE_VADDR + (elf_info.entry_point - elf_info.base_addr);

    return process;
}

pub fn elfTest() void {

    // Test with a more complex ELF that has multiple sections
    const elf_bytes = [_]u8{
        // ELF Header
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
        0x02, 0x00, // e_phnum - number of program headers (2 sections)
        0x00, 0x00, // e_shentsize
        0x00, 0x00, // e_shnum
        0x00, 0x00, // e_shstrndx

        // Program Header 1 - Code section
        0x01, 0x00, 0x00, 0x00, // p_type - PT_LOAD
        0x74, 0x00, 0x00, 0x00, // p_offset - offset in file
        0x00, 0x10, 0x40, 0x00, // p_vaddr - virtual address
        0x00, 0x10, 0x40, 0x00, // p_paddr - physical address
        0x04, 0x00, 0x00, 0x00, // p_filesz - size in file
        0x04, 0x00, 0x00, 0x00, // p_memsz - size in memory
        0x05, 0x00, 0x00, 0x00, // p_flags - PF_R | PF_X
        0x00, 0x10, 0x00, 0x00, // p_align - alignment

        // Program Header 2 - Data section
        0x01, 0x00, 0x00, 0x00, // p_type - PT_LOAD
        0x78, 0x00, 0x00, 0x00, // p_offset - offset in file
        0x00, 0x20, 0x40, 0x00, // p_vaddr - virtual address
        0x00, 0x20, 0x40, 0x00, // p_paddr - physical address
        0x04, 0x00, 0x00, 0x00, // p_filesz - size in file
        0x04, 0x00, 0x00, 0x00, // p_memsz - size in memory
        0x06, 0x00, 0x00, 0x00, // p_flags - PF_R | PF_W
        0x00, 0x10, 0x00, 0x00, // p_align - alignment

        // Code section (at offset 0x74)
        0xEB, 0xFE, 0x90, 0x90, // jmp $ + nops

        // Data section (at offset 0x78)
        0xDE, 0xAD, 0xBE, 0xEF, // some data
    };

    const process = loadElfProcess(&elf_bytes) orelse {
        out.println("Failed to load ELF process");
        return;
    };

    process.run();
}
