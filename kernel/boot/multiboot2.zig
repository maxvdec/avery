const sys = @import("system");
const mem = @import("memory");
const out = @import("output");

pub const TagType = enum(u32) {
    End = 0,
    MemoryMap = 6,
    Framebuffer = 8,
};

pub const BootInfo = packed struct {
    total_size: u32,
    reserved: u32,
};

pub const Tag = packed struct {
    typ: TagType,
    size: u32,
};

pub const MemoryMapEntry = packed struct {
    base_addr: u64,
    length: u64,
    typ: u32,
    reserved: u32,
};

pub const MemoryMapTag = packed struct {
    typ: TagType,
    size: u32,
    entry_size: u32,
    entry_version: u32,
};

pub const FramebufferTag = packed struct {
    typ: u32,
    size: u32,
    addr: u64,
    pitch: u32,
    width: u32,
    height: u32,
    bpp: u8,
    framebuffer_type: u8,
    reserved: u16,
};

pub fn getBootInfo(addr: u32) *const BootInfo {
    const bootInfo: *const BootInfo = @as(*const BootInfo, @ptrFromInt(addr));
    return bootInfo;
}

pub fn getMemoryMapTag(bootInfo: *const BootInfo) mem.Optional(*const MemoryMapTag) {
    @setRuntimeSafety(false);
    var addr: usize = @intFromPtr(bootInfo) + @sizeOf(BootInfo);
    const end_addr: usize = @intFromPtr(bootInfo) + bootInfo.total_size;

    while (addr < end_addr) {
        const tag = @as(*const Tag, @ptrFromInt(addr));

        if (tag.typ == TagType.End) {
            return mem.Optional(*const MemoryMapTag).none();
        }

        if (tag.typ == TagType.MemoryMap) {
            return mem.Optional(*const MemoryMapTag).some(@as(*const MemoryMapTag, @ptrFromInt(addr)));
        }

        const alignedSize = (tag.size + 7) & ~@as(usize, 7);
        addr += alignedSize;
    }

    return mem.Optional(*const MemoryMapTag).none();
}

pub fn getFramebufferTag(bootInfo: *const BootInfo) mem.Optional(*const FramebufferTag) {
    @setRuntimeSafety(false);
    var addr: usize = @intFromPtr(bootInfo) + @sizeOf(BootInfo);
    const end_addr: usize = @intFromPtr(bootInfo) + bootInfo.total_size;

    while (addr < end_addr) {
        const tag = @as(*const Tag, @ptrFromInt(addr));

        if (tag.typ == TagType.End) break;

        if (tag.typ == TagType.Framebuffer) {
            const framebuffer: *const FramebufferTag = @as(*const FramebufferTag, @ptrFromInt(addr));
            return mem.Optional(*const FramebufferTag).some(framebuffer);
        }

        const alignedSize = (tag.size + 7) & ~@as(usize, 7);
        addr += alignedSize;
    }

    return mem.Optional(*const FramebufferTag).none();
}

pub fn getAvailableMemory(memMap: MemoryMapTag) u64 {
    @setRuntimeSafety(false);
    var memCopy = memMap;
    const tag = &memCopy;
    const entry_size = tag.entry_size;
    const total_tag_size = tag.size;
    const entry_count = (total_tag_size - @sizeOf(MemoryMapTag)) / entry_size;

    var totalUsable: u64 = 0;
    var entry_ptr = @intFromPtr(tag) + @sizeOf(MemoryMapTag);

    var i: usize = 0;
    while (i < entry_count) : (i += 1) {
        const entry: *const MemoryMapEntry = @ptrFromInt(entry_ptr);
        if (entry.typ == 1) {
            totalUsable += entry.length;
        }

        entry_ptr += entry_size;
    }

    return totalUsable;
}

pub fn printMemoryMap(tag: *const MemoryMapTag) void {
    const entryCount = (tag.size - @sizeOf(MemoryMapTag)) / @sizeOf(MemoryMapEntry);
    const entries: [*]const MemoryMapEntry = @ptrFromInt(@intFromPtr(tag) + @sizeOf(MemoryMapTag));

    for (0..entryCount) |i| {
        const entry = entries[i];
        out.print("Base: ");
        out.printHex(entry.base_addr);
        out.print(", Length: ");
        out.printHex(entry.length);
        out.print(", Type: ");
        out.printHex(entry.typ);
        out.print(", Reserved: ");
        out.printHex(entry.reserved);
        out.print("\n");
    }
}

pub fn printFramebufferInfo(tag: *const FramebufferTag) void {
    out.print("Framebuffer Address: ");
    out.printHex(tag.addr);
    out.print("\nWidth: ");
    out.printHex(tag.width);
    out.print(", Height: ");
    out.printHex(tag.height);
    out.print(", Pitch: ");
    out.printHex(tag.pitch);
    out.print("\nBPP: ");
    out.printHex(tag.bpp);
    out.print(", Type: ");
    out.printHex(tag.framebuffer_type);
    out.print("\n");
}
