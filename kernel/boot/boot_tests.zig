const out = @import("output");
const virtmem = @import("virtual_mem");

pub fn vmm() void {
    @setRuntimeSafety(false);

    out.println("\n======= Virtual Memory Management Tests =======");
    out.print("Test I: Basic mapping.............");

    const test_virt_addr: u32 = 0x800000;
    const test_phys_addr: u32 = 0x300000; // 3MB mark
    const test_value: u32 = 0xDEADBEEF;

    virtmem.mapPage(test_virt_addr, test_phys_addr, virtmem.PAGE_PRESENT | virtmem.PAGE_WRITABLE) orelse {
        testFailed("Failed to map page\n");
        return;
    };

    if (virtmem.getPhysicalAddress(test_virt_addr).? != test_phys_addr) {
        testFailed("Failed to map page\n");
        return;
    }

    testPassed();

    out.print("Test II: Memory access through virtual address...............");
    const ptr: *volatile u32 = @ptrFromInt(test_virt_addr);

    ptr.* = test_value;

    const read_value = ptr.*;

    if (read_value != test_value) {
        testFailed("Failed to read value from virtual address\n");
        return;
    }
    testPassed();

    out.print("Test III: Unmapping page..................");

    virtmem.unmapPage(test_virt_addr);

    if (virtmem.getPhysicalAddress(test_virt_addr) != null) {
        testFailed("Failed to unmap page\n");
        return;
    }

    testPassed();

    out.print("Test IV: Virtual Memory Allocation..................");
    const allocation_size: usize = 8192; // 2 pages
    const alloc_addr = virtmem.allocateVirtualMemory(allocation_size, virtmem.PAGE_PRESENT | virtmem.PAGE_WRITABLE) orelse {
        testFailed("Failed to allocate virtual memory\n");
        return;
    };

    const alloc_ptr: *volatile u32 = @ptrFromInt(alloc_addr);
    alloc_ptr.* = test_value;
    const read_alloc_value = alloc_ptr.*;
    if (read_alloc_value != test_value) {
        testFailed("Failed to read value from allocated virtual memory\n");
        return;
    }

    testPassed();

    out.print("Test V: Freeing allocated virtual memory..................");
    virtmem.freeVirtualMemory(alloc_addr, allocation_size);

    if (virtmem.getPhysicalAddress(alloc_addr) != null) {
        testFailed("Failed to free allocated virtual memory\n");
        return;
    }

    testPassed();

    out.print("Test VI: Large allocation...................");
    const large_allocation_size: usize = 4096 * 4096; // 4096 pages (16MB)
    const large_alloc_addr = virtmem.allocateVirtualMemory(large_allocation_size, virtmem.PAGE_PRESENT | virtmem.PAGE_WRITABLE) orelse {
        testFailed("Failed to allocate large virtual memory\n");
        return;
    };
    const large_alloc_ptr: *volatile u32 = @ptrFromInt(large_alloc_addr);
    large_alloc_ptr.* = test_value;
    const read_large_alloc_value = large_alloc_ptr.*;

    if (read_large_alloc_value != test_value) {
        testFailed("Failed to read value from large allocated virtual memory\n");
        return;
    }
    testPassed();

    out.print("Test VII: Freeing large allocated virtual memory..................");
    virtmem.freeVirtualMemory(large_alloc_addr, large_allocation_size);
    if (virtmem.getPhysicalAddress(large_alloc_addr) != null) {
        testFailed("Failed to free large allocated virtual memory\n");
        return;
    }
    testPassed();

    out.println("=========================");
}

pub fn testFailed(message: []const u8) void {
    out.setTextColor(out.VgaTextColor.LightRed, out.VgaTextColor.Black);
    out.print(message);
    out.setTextColor(out.VgaTextColor.LightGray, out.VgaTextColor.Black);
}

pub fn testPassed() void {
    out.setTextColor(out.VgaTextColor.LightGreen, out.VgaTextColor.Black);
    out.print("OK\n");
    out.setTextColor(out.VgaTextColor.LightGray, out.VgaTextColor.Black);
}

pub fn runAll() void {
    vmm();
}
