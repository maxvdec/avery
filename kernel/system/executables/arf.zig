const mem = @import("memory");
const proc = @import("process");
const out = @import("output");
const vmm = @import("virtual_mem");
const kalloc = @import("kern_allocator");

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
};

pub const Fix = struct {
    name: []const u8,
    offset: usize,
};

pub const Executable = struct { header: Header, sections: []Section, symbols: []Symbol, libraries: []Library, fixes: []Fix, entryPoint: usize, extensions: []u8, library: bool, data: []const u8, fileSize: usize };

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
        const library = Library{
            .name = library_name,
            .visibility = library_visibility,
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
        out.printHex(extension);
        if (extension == 0xFF) {
            break; // End of extensions
        }
        exec.extensions = mem.append(u8, exec.extensions, extension);
    }

    exec.data = stream.getRemaining();

    return exec;
}

pub fn createProcess(executable: ?Executable) ?*proc.Process {
    if (executable == null) {
        return null;
    }

    const buffer = kalloc.requestKernel(executable.?.data.len) orelse {
        out.println("Failed to allocate memory for executable data.");
        return null;
    };

    for (0..executable.?.data.len) |i| {
        buffer[i] = executable.?.data[i];
    }

    // var lastAddress = executable.?.data.len + executable.?.entryPoint + 1;

    // for (executable.?.libraries) |lib| {
    //     switch (lib.visibility) {
    //         LIB_RESOLVED => continue,
    //         LIB_KERNEL => {
    //             // We need to load the kernel library
    //         },
    //     }
    // }

    const process = proc.Process.createProcess(buffer[0..executable.?.data.len]).?;
    return process;
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
        out.print("Name: ");
        out.println(section.name);
        out.print("Offset: ");
        out.printHex(@as(u32, section.offset));
        out.print(", Permissions: ");
        out.printHex(section.permission);
        out.println("");
    }
    out.println("===== Symbols =====");
    for (executable.?.symbols) |symbol| {
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
