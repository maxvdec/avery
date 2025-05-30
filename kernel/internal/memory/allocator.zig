const vmm = @import("virtual_mem");
const pmm = @import("physical_mem");
const out = @import("output");
const sys = @import("system");
const mem = @import("memory");

pub fn request(size: usize) ?[*]u8 {
    @setRuntimeSafety(false);
    const total_size = @sizeOf(usize) + size;
    const pages_needed = (total_size + pmm.PAGE_SIZE - 1) / pmm.PAGE_SIZE;

    // Allocate enough space + 1 page for the guard
    const virt_addr = vmm.allocVirtual(
        pages_needed * pmm.PAGE_SIZE + pmm.PAGE_SIZE,
        vmm.PAGE_PRESENT | vmm.PAGE_RW,
    ) orelse {
        out.print("Failed to allocate virtual memory\n");
        return null;
    };

    const guard_page_addr = virt_addr + (pages_needed * pmm.PAGE_SIZE);
    vmm.unmapPage(guard_page_addr);

    out.preserveMode();
    out.switchToSerial();
    out.print("Allocated virtual memory at address: ");
    out.printHex(virt_addr);
    out.print(" with size: ");
    out.printHex(size);
    out.println("");
    out.restoreMode();

    // Store metadata at the beginning
    const metadata = @as(*usize, @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(virt_addr)))));
    metadata.* = size;

    const user_data_start = virt_addr + @sizeOf(usize);

    for (0..size) |i| {
        const byte_ptr: *u8 = @ptrFromInt(user_data_start + i);
        byte_ptr.* = 0;
    }

    return @as([*]u8, @ptrFromInt(user_data_start));
}

pub fn store(comptime T: type) *T {
    @setRuntimeSafety(false);
    const size = @sizeOf(T);
    const ptr = request(size) orelse {
        sys.panic("Failed to allocate memory for object");
    };

    return @alignCast(@ptrCast(ptr));
}

pub fn storeMany(comptime T: type, count: usize) [*]T {
    @setRuntimeSafety(false);
    const size = @sizeOf(T) * count;
    const ptr = request(size) orelse {
        sys.panic("Failed to allocate memory for array");
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
