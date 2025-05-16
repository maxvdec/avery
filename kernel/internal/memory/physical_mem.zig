const multiboot2 = @import("multiboot2");
const mem = @import("memory");
const out = @import("output");

pub const PAGE_SIZE: usize = 4096;
pub const MAX_MEMORY: usize = 4 * 1024 * 1024 * 1024; // 4GB

var bitmap: []u8 = undefined;
var total_pages: usize = 0;

pub fn init(memoryMap: *const multiboot2.MemoryMapTag, kernelEnd: u32) void {
    @setRuntimeSafety(false);
    var total_memory: usize = 0;
    const entry_start = @intFromPtr(memoryMap) + @sizeOf(multiboot2.MemoryMapTag);
    const entry_end = @intFromPtr(memoryMap) + memoryMap.size;

    var ptr = entry_start;
    while (ptr < entry_end) : (ptr += memoryMap.entry_size) {
        const entry = @as(*const multiboot2.MemoryMapEntry, @ptrFromInt(ptr));
        if (entry.typ == 1) {
            total_memory += @as(usize, @intCast(entry.length));
        }
    }

    total_pages = total_memory / PAGE_SIZE;
    const bitmap_size_bytes = (total_pages + 7) / 8;

    const bitmap_start = mem.alignUp(kernelEnd, PAGE_SIZE);
    bitmap = @as([*]u8, @ptrFromInt(bitmap_start))[0..bitmap_size_bytes];

    for (bitmap) |*b| b.* = 0;

    ptr = entry_start;

    while (ptr < entry_end) : (ptr += memoryMap.entry_size) {
        const entry = @as(*const multiboot2.MemoryMapEntry, @ptrFromInt(ptr));
        const base = entry.base_addr;
        const length = entry.length;
        const mem_type = entry.typ;

        if (mem_type != 1) {
            markRegionUsed(base, length);
        }
    }

    const used_end = bitmap_start + bitmap_size_bytes;
    markRegionUsed(0, used_end);
}

fn markRegionUsed(base: u64, length: u64) void {
    @setRuntimeSafety(false);
    const start_page = base / PAGE_SIZE;
    const end_page = (base + length + PAGE_SIZE - 1) / PAGE_SIZE;
    for (@as(usize, @intCast(start_page))..@as(usize, @intCast(end_page))) |page| {
        bitmapSet(page);
    }
}

inline fn bitmapSet(page: usize) void {
    @setRuntimeSafety(false);
    const shift: u3 = @intCast(page % 8);
    bitmap[page / 8] |= @as(u8, 1) << shift;
}

inline fn bitmapClear(page: usize) void {
    @setRuntimeSafety(false);
    const shift: u3 = @intCast(page % 8);
    bitmap[page / 8] &= ~(@as(u8, 1) << shift);
}

inline fn bitmapTest(page: usize) bool {
    @setRuntimeSafety(false);
    const shift: u3 = @intCast(page % 8);
    return (bitmap[page / 8] & (@as(u8, 1) << shift)) != 0;
}

pub fn allocPage() ?usize {
    @setRuntimeSafety(false);
    for (0..total_pages) |page| {
        if (!bitmapTest(page)) {
            bitmapSet(page);
            return page * PAGE_SIZE;
        }
    }
    return null;
}

pub fn freePage(addr: usize) void {
    @setRuntimeSafety(false);
    const page = addr / PAGE_SIZE;
    if (page < total_pages) {
        bitmapClear(page);
    }
}
