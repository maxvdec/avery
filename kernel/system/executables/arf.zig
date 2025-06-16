const mem = @import("memory");
const proc = @import("process");
const out = @import("output");
const vmm = @import("virtual_mem");
const kalloc = @import("kern_allocator");
const ata = @import("ata");
const pathfn = @import("path");
const fs = @import("vfs");
const sch = @import("scheduler");

pub const Architecture = enum(u8) {
    i386 = 1,
    x86_64 = 2,
    armv7 = 3,
    aarch64 = 4,
    Unknown = 0,
};

pub const Header = struct {
    version: []const u8,
    architecture: Architecture,
    hostArchitecture: Architecture,
};

pub const SEC_READ = 0x0;
pub const SEC_WRITE = 0x2;
pub const SEC_EXECUTE = 0x4;
pub const SEC_INFO = 0x10;

pub const Section = struct {
    name: []const u8,
    offset: usize,
    permission: u8,
};

pub const SYM_RESOLVED = 0x0;
pub const SYM_UNRESOLVED = 0x1;
pub const SYM_MERGED = 0x2;

pub const SYM_LOCAL = 0x0;
pub const SYM_GLOBAL = 0x1;
pub const SYM_MIXED = 0x2;

pub const Symbol = struct {
    name: []const u8,
    resolution: u8,
    typ: u8,
    offset: usize,
};

const LIB_RESOLVED = 0x0;
const LIB_KERNEL = 0xFF;

pub const Library = struct {
    name: []const u8,
    visibility: u8,
    loadedAt: usize = 0,
    path: []const u8,
};

pub const Fix = struct {
    name: []const u8,
    offset: usize,
};

pub const Executable = struct { header: Header, sections: []Section, symbols: []Symbol, libraries: []Library, fixes: []Fix, entryPoint: usize, extensions: []u8, library: bool, data: []const u8, fileSize: usize, offsetEntryPoint: usize };

pub fn loadExecutable(data: []const u8) ?Executable {
    @setRuntimeSafety(false);
    var exec = Executable{
        .header = Header{
            .version = "ARF 0.1.0",
            .architecture = Architecture.x86_64,
            .hostArchitecture = Architecture.x86_64,
        },
        .sections = &.{},
        .symbols = &.{},
        .libraries = &.{},
        .fixes = &.{},
        .entryPoint = 0,
        .extensions = &.{},
        .library = false,
        .data = &.{},
        .fileSize = data.len,
        .offsetEntryPoint = 0,
    };

    // Parse the header
    var stream = mem.Stream(u8).init(data);
    stream.seek(0);

    const magic = stream.get(6).?;
    if (mem.compareBytes(u8, magic[0..3], "ARF")) {
        exec.header.version = magic[3..];
    } else if (mem.compareBytes(u8, magic[0..3], "ARL")) {
        exec.header.version = magic[3..];
        exec.library = true;
    } else {
        return null;
    }

    const arch = stream.get(1).?[0];
    const host_arch = stream.get(1).?[0];
    exec.header.architecture = switch (arch) {
        1 => Architecture.i386,
        2 => Architecture.x86_64,
        3 => Architecture.armv7,
        4 => Architecture.aarch64,
        else => Architecture.Unknown, // Unsupported architecture
    };
    exec.header.hostArchitecture = switch (host_arch) {
        1 => Architecture.i386,
        2 => Architecture.x86_64,
        3 => Architecture.armv7,
        4 => Architecture.aarch64,
        else => Architecture.Unknown, // Unsupported host architecture
    };

    const entry_point_bytes = stream.get(4).?;
    const entry_point = mem.reinterpretBytes(u32, entry_point_bytes, false).unwrap();
    exec.entryPoint = @as(usize, entry_point);

    while (stream.get(1).?[0] == 0xFF) {
        const section_name = stream.getUntil(0x00).?;
        stream.skip(1);
        const section_offset = stream.get(4).?;
        const section_permission = stream.get(1).?[0];

        if (section_name.len == 0 or section_offset.len != 4) {
            return null; // Invalid section data
        }

        const section = Section{
            .name = section_name,
            .offset = mem.reinterpretBytes(usize, section_offset, false).unwrap(),
            .permission = section_permission,
        };
        exec.sections = mem.append(Section, exec.sections, section);
    }

    stream.goBack(1);

    while (stream.get(1).?[0] == 0xEE) {
        const symbol_name = stream.getUntil(0x00).?;
        stream.skip(1);
        const symbol_resolution = stream.get(1).?[0];
        const symbol_type = stream.get(1).?[0];
        const symbol_offset_bytes = stream.get(4).?;

        if (symbol_name.len == 0 or symbol_offset_bytes.len != 4) {
            return null; // Invalid symbol data
        }
        const symbol_offset = mem.reinterpretBytes(usize, symbol_offset_bytes, false).unwrap();
        const symbol = Symbol{
            .name = symbol_name,
            .resolution = symbol_resolution,
            .typ = symbol_type,
            .offset = @as(usize, symbol_offset),
        };
        exec.symbols = mem.append(Symbol, exec.symbols, symbol);
    }

    stream.goBack(1);

    while (stream.get(1).?[0] == 0xDD) {
        const library_name = stream.getUntil(0x00).?;
        stream.skip(1);
        const library_visibility = stream.get(1).?[0];

        if (library_name.len == 0) {
            return null; // Invalid library data
        }

        var library_path: []const u8 = "";
        if (library_visibility == LIB_KERNEL) {
            library_path = stream.getUntil(0x00).?;
        }
        const library = Library{
            .name = library_name,
            .visibility = library_visibility,
            .path = library_path,
        };
        exec.libraries = mem.append(Library, exec.libraries, library);
    }

    stream.goBack(1);

    while (stream.get(1).?[0] == 0xCC) {
        const fix_name = stream.getUntil(0x00).?;
        stream.skip(1);
        const fix_offset_bytes = stream.get(4).?;

        if (fix_name.len == 0 or fix_offset_bytes.len != 4) {
            return null; // Invalid fix data
        }
        const fix_offset = mem.reinterpretBytes(usize, fix_offset_bytes, false).unwrap();
        const fix = Fix{
            .name = fix_name,
            .offset = @as(usize, fix_offset),
        };
        exec.fixes = mem.append(Fix, exec.fixes, fix);
    }

    while (true) {
        const extension = stream.get(1).?[0];
        if (extension == 0xFF) {
            break; // End of extensions
        }
        exec.extensions = mem.append(u8, exec.extensions, extension);
    }

    var text_offset: usize = 0;
    for (exec.sections) |section| {
        if (section.permission & SEC_EXECUTE != 0) {
            text_offset = section.offset;
            break;
        }
    }

    exec.data = stream.getRemaining();

    return exec;
}

pub fn createProcess(executable: ?Executable, disk: *ata.AtaDrive, startPriority: sch.ProcessPriority) ?*proc.Process {
    if (executable == null) {
        out.println("Invalid executable data.");
        return null;
    }

    const exec = executable.?;

    var total_size: usize = exec.data.len;
    var kernel_libraries = mem.Array([]const u8).init();

    for (exec.libraries) |library| {
        switch (library.visibility) {
            LIB_RESOLVED => continue,
            LIB_KERNEL => {
                const libData = loadKernelLibrary(library.name, library.path, disk) orelse {
                    out.print("Failed to load kernel library: ");
                    out.println(library.name);
                    return null;
                };
                kernel_libraries.append(libData);
                total_size += libData.len;
            },
            else => continue,
        }
    }

    const buffer = kalloc.requestKernel(total_size) orelse {
        out.println("Failed to allocate memory for executable.");
        return null;
    };

    for (0..exec.data.len) |i| {
        buffer[i] = exec.data[i];
    }

    var current_offset = exec.data.len;
    var libraryIndex: usize = 0;

    for (exec.libraries) |lib| {
        switch (lib.visibility) {
            LIB_RESOLVED => continue,
            LIB_KERNEL => {
                const libData = kernel_libraries.get(libraryIndex).?;
                libraryIndex += 1;

                for (0..libData.len) |i| {
                    buffer[current_offset + i] = libData[i];
                }

                const libExecutable = loadExecutable(libData);
                if (libExecutable) |libExec| {
                    updateSymbolsForLibrary(buffer[0..total_size], exec, current_offset, libExec);
                }

                current_offset += libData.len;
            },
            else => continue,
        }
    }

    const process = proc.Process.createProcess(buffer[0..total_size], exec.entryPoint, startPriority).?;
    return process;
}

fn updateSymbolsForLibrary(buffer: []u8, exec: Executable, libOffset: usize, libExec: Executable) void {
    for (exec.symbols) |symbol| {
        if (symbol.resolution == SYM_UNRESOLVED) {
            for (libExec.symbols) |libSymbol| {
                if (mem.compareBytes(u8, symbol.name, libSymbol.name) and
                    libSymbol.resolution == SYM_RESOLVED)
                {
                    const actualAddress = libOffset + libSymbol.offset;

                    const addressBytes = mem.reinterpretToBytes(u32, @as(u32, @intCast(actualAddress)));
                    for (0..4) |i| {
                        if (symbol.offset + i < exec.data.len) {
                            buffer[symbol.offset + i] = addressBytes[i];
                        }
                    }

                    break;
                }
            }
        }
    }

    for (exec.fixes) |fix| {
        for (libExec.symbols) |libSymbol| {
            if (mem.compareBytes(u8, fix.name, libSymbol.name) and
                libSymbol.resolution == SYM_RESOLVED)
            {
                const actualAddress = libOffset + libSymbol.offset;
                const addressBytes = mem.reinterpretToBytes(u32, @as(u32, @intCast(actualAddress)));

                for (0..4) |i| {
                    if (fix.offset + i < exec.data.len) {
                        buffer[fix.offset + i] = addressBytes[i];
                    }
                }

                break;
            }
        }
    }
}

fn loadKernelLibrary(name: []const u8, path: []const u8, disk: *ata.AtaDrive) ?[]const u8 {
    @setRuntimeSafety(false);
    const full_path = pathfn.joinPaths(path, mem.joinBytes(u8, "./", name));
    const file = fs.readFile(disk, 0, full_path) orelse {
        out.print("Failed to open kernel library: ");
        out.println(name);
        return null;
    };
    return file;
}

pub fn printArchitecture(arch: Architecture) void {
    const architecture = switch (arch) {
        .i386 => "i386",
        .x86_64 => "x86_64",
        .armv7 => "armv7",
        .aarch64 => "aarch64",
        else => "Unknown Architecture",
    };
    out.println(architecture);
}

pub fn printInformation(executable: ?Executable) void {
    if (executable == null) {
        out.println("Invalid executable data.");
        return;
    }
    out.println("Executable Information:");
    if (executable.?.library) {
        out.println("This is an ARL library.");
    } else {
        out.println("This is an ARF executable.");
    }
    out.print("Version: ");
    out.println(executable.?.header.version);
    out.print("Library: ");
    out.println(if (executable.?.library) "Yes" else "No");
    out.print("Architecture: ");
    printArchitecture(executable.?.header.architecture);
    if (executable.?.header.architecture == Architecture.i386) {
        out.println("This executable is supported by your kernel.");
    }
    out.print("Host Architecture: ");
    printArchitecture(executable.?.header.hostArchitecture);
    out.print("Entry Point: ");
    out.printHex(@as(u32, executable.?.entryPoint));
    out.println("");
    if (executable.?.entryPoint != vmm.USER_CODE_VADDR) {
        out.println("Warning: The entry point is not the standard for Avery. Try 0x400000");
    }
    out.println("===== Sections =====");
    for (executable.?.sections) |section| {
        if (mem.startsWith(u8, section.name, "_")) {
            continue;
        }
        if (mem.compareBytes(u8, section.name, ".symtab") or
            mem.compareBytes(u8, section.name, ".strtab") or
            mem.compareBytes(u8, section.name, ".shstrtab"))
        {
            continue; // Skip symbol tables and string tables

        }
        out.print("Name: ");
        out.println(section.name);
        out.print("Address: ");
        out.printHex(@as(u32, section.offset));
        out.print(", Permissions: ");
        out.printHex(section.permission);
        out.println("");
    }
    out.println("===== Symbols =====");
    for (executable.?.symbols) |symbol| {
        if (mem.startsWith(u8, symbol.name, "_")) {
            continue;
        }

        out.print("Name: ");
        out.println(symbol.name);
        out.print("Resolution: ");
        switch (symbol.resolution) {
            SYM_RESOLVED => out.println("Resolved"),
            SYM_UNRESOLVED => out.println("Unresolved"),
            SYM_MERGED => out.println("Merged"),
            else => out.println("Unknown Resolution"),
        }
        out.print("Type: ");
        switch (symbol.typ) {
            SYM_LOCAL => out.println("Local"),
            SYM_GLOBAL => out.println("Global"),
            SYM_MIXED => out.println("Mixed"),
            else => out.println("Unknown Type"),
        }
        out.print("Offset: ");
        out.printHex(@as(u32, symbol.offset));
        out.println("");
    }
    out.println("===== Libraries =====");
    for (executable.?.libraries) |library| {
        out.print("Name: ");
        out.println(library.name);
        out.print("Visibility: ");
        switch (library.visibility) {
            LIB_RESOLVED => out.println("Resolved"),
            LIB_KERNEL => out.println("Kernel"),
            else => out.println("Unknown Visibility"),
        }
    }
    out.println("===== Fixes =====");
    for (executable.?.fixes) |fix| {
        out.print("Name: ");
        out.println(fix.name);
        out.print("Offset: ");
        out.printHex(@as(u32, fix.offset));
        out.println("");
    }
    out.println("===== Extensions =====");
    for (executable.?.extensions) |extension| {
        out.print("Extension: ");
        out.printHex(extension);
        out.println("");
    }
}
