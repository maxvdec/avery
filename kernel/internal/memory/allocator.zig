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

    out.print("Allocated virtual memory at: ");
    out.printHex(virt_addr);
    out.print("\n");
    out.print("Which in turn maps to physical memory at: ");
    const phys_addr = vmm.translate(virt_addr).?;
    out.printHex(phys_addr);
    out.print("\n");

    const pages_needed = (size + pmm.PAGE_SIZE - 1) / pmm.PAGE_SIZE;

    const guard_page_addr = virt_addr + (pages_needed * pmm.PAGE_SIZE);
    vmm.unmapPage(guard_page_addr);

    const metadata = @as(*usize, @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(virt_addr)))));
    metadata.* = size;

    // Clean the memory
    for (0..size) |i| {
        const byte_ptr: *u8 = @ptrFromInt(virt_addr + i);
        byte_ptr.* = 0;
    }

    return @as([*]u8, @ptrFromInt(virt_addr + @sizeOf(usize)));
}

pub fn store(comptime T: type) *T {
    @setRuntimeSafety(false);
    const size = @sizeOf(T);
    const ptr = request(size) orelse {
        sys.panic("Failed to allocate memory for object");
    };

    return @alignCast(@ptrCast(ptr));
}

pub fn free(ptr: [*]u8) void {
    @setRuntimeSafety(false);

    const addr_with_metadata = @intFromPtr(ptr) - @sizeOf(usize);

    const metadata = @as(*usize, @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(addr_with_metadata)))));
    const size = metadata.*;

    vmm.freeVirtual(addr_with_metadata, size + pmm.PAGE_SIZE);
}
