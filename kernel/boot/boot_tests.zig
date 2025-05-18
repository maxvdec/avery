const out = @import("output");
const virtmem = @import("virtual_mem");
const pmm = @import("physical_mem");

pub fn vmm() void {
    @setRuntimeSafety(false);

    out.println("\n======= Virtual Memory Management Tests =======");
    out.print("Test I: Basic mapping.............");

    const test_virt_addr: u32 = 0x800000;
    const test_phys_addr: u32 = 0x300000; // 3MB mark
    const test_value: u32 = 0xDEADBEEF;

    virtmem.mapPage(test_virt_addr, test_phys_addr, virtmem.PAGE_PRESENT | virtmem.PAGE_RW);

    if (virtmem.translate(test_virt_addr).? != test_phys_addr) {
        testFailed("Failed to map page. Physical address is off\n");
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

    if (virtmem.translate(test_virt_addr) != null) {
        testFailed("Failed to unmap page\n");
        return;
    }

    testPassed();

    out.println("=========================");
}

pub fn vmm_alloc_tests() void {
    @setRuntimeSafety(false);

    out.println("\n======= Virtual Memory Allocation Tests =======");

    // Test 1: Allocate 1 page and verify mapping
    out.print("Test I: Allocate 1 page.............");
    const size1 = pmm.PAGE_SIZE;
    const flags = virtmem.PAGE_PRESENT | virtmem.PAGE_RW;
    const addr1 = virtmem.allocVirtual(size1, flags) orelse {
        testFailed("Allocation failed\n");
        return;
    };

    if (virtmem.translate(addr1) == null) {
        testFailed("Allocation did not map any page\n");
        return;
    }
    testPassed();

    // Test 2: Write and read memory at allocated virtual address
    out.print("Test II: Access allocated memory...............");
    const ptr1: *volatile u32 = @ptrFromInt(addr1);
    const test_val1: u32 = 0x12345678;
    ptr1.* = test_val1;
    const read_val1 = ptr1.*;
    if (read_val1 != test_val1) {
        testFailed("Read value does not match written value\n");
        return;
    }
    testPassed();

    // Test 3: Allocate multiple pages (e.g., 3 pages)
    out.print("Test III: Allocate multiple pages (3 pages)...........");
    const size3 = pmm.PAGE_SIZE * 3;
    const addr3 = virtmem.allocVirtual(size3, flags) orelse {
        testFailed("Allocation of multiple pages failed\n");
        return;
    };

    // Check each page is mapped
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        if (virtmem.translate(addr3 + i * pmm.PAGE_SIZE) == null) {
            testFailed("Pag  in multi-page allocation not mapped\n");
            return;
        }
    }
    testPassed();

    // Test 4: Free allocated pages and verify unmapped
    out.print("Test IV: Free allocated pages and verify unmapping......");
    virtmem.freeVirtual(addr3, size3);

    i = 0;
    while (i < 3) : (i += 1) {
        if (virtmem.translate(addr3 + i * pmm.PAGE_SIZE) != null) {
            testFailed("Page  still mapped after free\n");
            return;
        }
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
    vmm_alloc_tests();
}
