const vmm = @import("virtual_mem");
const pmm = @import("physical_mem");
const out = @import("output");
const sys = @import("system");
const mem = @import("memory");

pub fn request(size: usize) ?[*]u8 {
    @setRuntimeSafety(false);
    const virt_addr = vmm.allocVirtual(size + pmm.PAGE_SIZE, vmm.PAGE_PRESENT | vmm.PAGE_RW) orelse {
        out.print("Failed to allocate virtual memory\n");
        return null;
    };

    const pages_needed = (size + pmm.PAGE_SIZE - 1) / pmm.PAGE_SIZE;

    const guard_page_addr = virt_addr + (pages_needed * pmm.PAGE_SIZE);
    vmm.unmapPage(guard_page_addr);

    const metadata = @as(*usize, @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(virt_addr)))));
    metadata.* = size;

    return @as([*]u8, @ptrFromInt(virt_addr + @sizeOf(usize)));
}

pub fn free(ptr: [*]u8) void {
    @setRuntimeSafety(false);

    const addr_with_metadata = @intFromPtr(ptr) - @sizeOf(usize);

    const metadata = @as(*usize, @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(addr_with_metadata)))));
    const size = metadata.*;

    vmm.freeVirtual(addr_with_metadata, size + pmm.PAGE_SIZE);
}
