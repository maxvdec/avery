const mem = @import("memory");
const pmm = @import("physical_mem");
const out = @import("output");
const PAGE_SIZE = 4096;

pub const PAGE_PRESENT = 1 << 0;
pub const PAGE_RW = 1 << 1;
pub const PAGE_USER = 1 << 2;

pub const USER_SPACE_START: usize = 0x400000;
pub const USER_SPACE_END: usize = 0x80000000;
pub const KERNEL_MEM_BASE: usize = 0xC0000000;

pub var page_directory: *[1024]u32 = undefined;

var next_free_virt: usize = 0x1000000;
var next_user_virt: usize = USER_SPACE_START;

pub const PageDirectory = struct {
    physical: usize,
    virtual: usize,
};

pub fn init() void {
    @setRuntimeSafety(false);

    const pd_physical = pmm.allocPage() orelse unreachable;
    page_directory = @as(*[1024]u32, @ptrFromInt(pd_physical));

    for (page_directory) |*entry| entry.* = 0;

    const pt_physical = pmm.allocPage() orelse unreachable;
    const pt = @as(*[1024]u32, @ptrFromInt(pt_physical));

    for (0..1024) |i| {
        pt[i] = (i * PAGE_SIZE) | PAGE_PRESENT | PAGE_RW | PAGE_USER;
    }

    page_directory[0] = pt_physical | PAGE_PRESENT | PAGE_RW | PAGE_USER;

    loadPageDirectory(pd_physical);
    enablePaging();
}

pub fn mapPage(virt: usize, phys: usize, flags: u32) void {
    @setRuntimeSafety(false);
    const pd_index = (virt >> 22) & 0x3FF;
    const pt_index = (virt >> 12) & 0x3FF;

    var pt: *[1024]u32 = undefined;

    if ((page_directory[pd_index] & PAGE_PRESENT) == 0) {
        const new_pt_phys = pmm.allocPage() orelse unreachable;
        page_directory[pd_index] = new_pt_phys | PAGE_PRESENT | PAGE_RW | PAGE_USER;
        pt = @as(*[1024]u32, @ptrFromInt(new_pt_phys));
        for (pt) |*e| e.* = 0;
    } else {
        const pt_phys = page_directory[pd_index] & 0xFFFFF000;
        pt = @as(*[1024]u32, @ptrFromInt(pt_phys));
    }

    pt[pt_index] = (phys & 0xFFFFF000) | (flags & 0xFFF);
    invlpg(virt);
}

pub fn allocVirtualRange(virt_start: usize, phys_start: usize, num_pages: usize, flags: u32) void {
    var i: usize = 0;
    while (i < num_pages) : (i += 1) {
        mapPage(virt_start + i * PAGE_SIZE, phys_start + i * PAGE_SIZE, flags);
    }
}

pub fn freeVirtualRange(virt_start: usize, num_pages: usize) void {
    var i: usize = 0;
    while (i < num_pages) : (i += 1) {
        unmapPage(virt_start + i * PAGE_SIZE);
    }
}

pub fn allocVirtual(size: usize, flags: u32) ?usize {
    @setRuntimeSafety(false);
    const pages_needed = (size + PAGE_SIZE - 1) / PAGE_SIZE;
    const virt_addr = next_free_virt;

    if (virt_addr + (pages_needed * PAGE_SIZE) >= KERNEL_MEM_BASE) {
        out.print("Virtual memory exhausted!\n");
        return null;
    }

    var i: usize = 0;
    while (i < pages_needed) : (i += 1) {
        const phys = pmm.allocPage() orelse {
            var j: usize = 0;
            while (j < i) : (j += 1) {
                unmapPage(virt_addr + j * PAGE_SIZE);
            }
            return null;
        };
        mapPage(virt_addr + i * PAGE_SIZE, phys, flags | PAGE_PRESENT | PAGE_USER);
    }

    next_free_virt += pages_needed * PAGE_SIZE;

    return virt_addr;
}

pub fn freeVirtual(virt_start: usize, size: usize) void {
    const pages = (size + PAGE_SIZE - 1) / PAGE_SIZE;

    var i: usize = 0;
    while (i < pages) : (i += 1) {
        const phys = translate(virt_start + i * PAGE_SIZE);
        if (phys) |p| {
            pmm.freePage(p);
        }
        unmapPage(virt_start + i * PAGE_SIZE);
    }
}

pub fn unmapPage(virt: usize) void {
    @setRuntimeSafety(false);
    const pd_index = (virt >> 22) & 0x3FF;
    const pt_index = (virt >> 12) & 0x3FF;

    if ((page_directory[pd_index] & PAGE_PRESENT) == 0) return;

    const pt_phys = page_directory[pd_index] & 0xFFFFF000;
    const pt = @as(*[1024]u32, @ptrFromInt(pt_phys));

    pt[pt_index] = 0;
    invlpg(virt);
}

pub fn translate(virt: usize) ?usize {
    @setRuntimeSafety(false);
    const pd_index = (virt >> 22) & 0x3FF;
    const pt_index = (virt >> 12) & 0x3FF;

    if ((page_directory[pd_index] & PAGE_PRESENT) == 0) return null;
    const pt_phys = page_directory[pd_index] & 0xFFFFF000;
    const pt = @as(*[1024]u32, @ptrFromInt(pt_phys));

    if ((pt[pt_index] & PAGE_PRESENT) == 0) return null;
    const phys_base = pt[pt_index] & 0xFFFFF000;
    const offset = virt & 0xFFF;
    return phys_base + offset;
}

pub fn loadPageDirectory(phys_addr: usize) void {
    @setRuntimeSafety(false);
    const pd_virt = mapPhysicalPage(phys_addr) orelse unreachable;
    page_directory = @as(*[1024]u32, @ptrFromInt(pd_virt));

    asm volatile ("mov %[addr], %%cr3"
        :
        : [addr] "r" (phys_addr),
        : "memory"
    );
}

pub fn enablePaging() void {
    var cr0: usize = 0;
    asm volatile ("mov %%cr0, %[out]"
        : [out] "=r" (cr0),
        :
        : "memory"
    );

    cr0 |= 0x80000000;

    asm volatile ("mov %[in], %%cr0"
        :
        : [in] "r" (cr0),
        : "memory"
    );
}

pub fn invlpg(addr: usize) void {
    asm volatile ("invlpg (%[addr])"
        :
        : [addr] "r" (addr),
        : "memory"
    );
}

fn getPageDirectoryIndex(virt_addr: usize) usize {
    return (virt_addr >> 22) & 0x3FF;
}

fn getPageTableIndex(virt_addr: usize) usize {
    return (virt_addr >> 12) & 0x3FF;
}

pub fn mapMemory(phys_addr: usize, size: usize) u32 {
    if (phys_addr % PAGE_SIZE != 0) return 0;

    const pages_needed = (size + PAGE_SIZE - 1) / PAGE_SIZE;
    const flags = PAGE_PRESENT | PAGE_RW | PAGE_USER;

    const virt_addr = allocVirtual(size, flags) orelse return 0;

    var i: usize = 0;
    while (i < pages_needed) : (i += 1) {
        mapPage(virt_addr + i * PAGE_SIZE, phys_addr + i * PAGE_SIZE, flags);
    }

    return virt_addr;
}

pub fn mapKernelMemory(phys_addr: usize, size: usize) u32 {
    if (phys_addr % PAGE_SIZE != 0) return 0;

    const pages_needed = (size + PAGE_SIZE - 1) / PAGE_SIZE;
    const flags = PAGE_PRESENT | PAGE_RW;

    const virt_addr = KERNEL_MEM_BASE + (next_free_virt - 0x1000000);

    var i: usize = 0;
    while (i < pages_needed) : (i += 1) {
        mapPage(virt_addr + i * PAGE_SIZE, phys_addr + i * PAGE_SIZE, flags);
    }

    next_free_virt += pages_needed * PAGE_SIZE;

    return virt_addr;
}

pub fn allocUserPages(size: usize) ?usize {
    @setRuntimeSafety(false);
    const pages_needed = (size + PAGE_SIZE - 1) / PAGE_SIZE;

    if (next_user_virt + (pages_needed * PAGE_SIZE) >= USER_SPACE_END) {
        out.print("User virtual memory exhausted!\n");
        return null;
    }

    const virt_addr = next_user_virt;

    var i: usize = 0;
    while (i < pages_needed) : (i += 1) {
        const phys = pmm.allocPage() orelse {
            var j: usize = 0;
            while (j < i) : (j += 1) {
                const cleanup_virt = virt_addr + j * PAGE_SIZE;
                if (translate(cleanup_virt)) |p| {
                    pmm.freePage(p);
                }
                unmapPage(cleanup_virt);
            }
            return null;
        };
        mapPage(virt_addr + i * PAGE_SIZE, phys, PAGE_PRESENT | PAGE_RW | PAGE_USER);
    }

    next_user_virt += pages_needed * PAGE_SIZE;

    return virt_addr;
}

pub fn freeUserPages(virt_start: usize, size: usize) void {
    const pages = (size + PAGE_SIZE - 1) / PAGE_SIZE;

    var i: usize = 0;
    while (i < pages) : (i += 1) {
        const phys = translate(virt_start + i * PAGE_SIZE);
        if (phys) |p| {
            pmm.freePage(p);
        }
        unmapPage(virt_start + i * PAGE_SIZE);
    }
}

pub fn physicalToVirtual(phys: usize) ?usize {
    @setRuntimeSafety(false);

    for (0..1024) |pd_index| {
        if ((page_directory[pd_index] & PAGE_PRESENT) == 0) continue;

        const pt_phys = page_directory[pd_index] & 0xFFFFF000;
        const pt = @as(*[1024]u32, @ptrFromInt(pt_phys));

        for (0..1024) |pt_index| {
            if ((pt[pt_index] & PAGE_PRESENT) == 0) continue;

            const phys_base = pt[pt_index] & 0xFFFFF000;
            if (phys_base == (phys & 0xFFFFF000)) {
                const offset = phys & 0xFFF;
                return ((pd_index << 22) | (pt_index << 12)) + offset;
            }
        }
    }

    return null;
}

pub fn mapPhysicalPage(phys_addr: usize) ?usize {
    @setRuntimeSafety(false);

    if (translate(phys_addr)) |existing_virt| {
        return existing_virt;
    }

    const aligned_phys = phys_addr & 0xFFFFF000;
    const offset = phys_addr & 0xFFF;

    const temp_virt = allocVirtual(PAGE_SIZE, PAGE_PRESENT | PAGE_RW | PAGE_USER) orelse return null;

    unmapPage(temp_virt);

    mapPage(temp_virt, aligned_phys, PAGE_PRESENT | PAGE_RW | PAGE_USER);

    return temp_virt + offset;
}

pub fn unmapPhysicalPage(virt_addr: usize) void {
    @setRuntimeSafety(false);

    if (translate(virt_addr)) |phys| {
        if ((virt_addr & 0xFFFFF000) != (phys & 0xFFFFF000)) {
            unmapPage(virt_addr & 0xFFFFF000);
        }
    }
}

pub fn mapPhysicalPageSimple(phys_addr: usize) usize {
    @setRuntimeSafety(false);
    return phys_addr;
}

pub fn copyUserMappingsToNewPD(virt_start: usize, size: usize, new_pd: *[1024]u32) void {
    const pages = (size + PAGE_SIZE - 1) / PAGE_SIZE;

    var i: usize = 0;
    while (i < pages) : (i += 1) {
        const virt = virt_start + i * PAGE_SIZE;

        const phys = translate(virt) orelse continue;

        mapPageInPD(virt, phys, PAGE_PRESENT | PAGE_RW | PAGE_USER, new_pd);
    }
}

pub fn mapPageInPD(virt: usize, phys: usize, flags: u32, target_pd: *[1024]u32) void {
    @setRuntimeSafety(false);
    const pd_index = (virt >> 22) & 0x3FF;
    const pt_index = (virt >> 12) & 0x3FF;

    var pt: *[1024]u32 = undefined;

    if ((target_pd[pd_index] & PAGE_PRESENT) == 0) {
        const new_pt_phys = pmm.allocPage() orelse unreachable;
        target_pd[pd_index] = new_pt_phys | PAGE_PRESENT | PAGE_RW | PAGE_USER;

        const pt_virt = mapPhysicalPage(new_pt_phys) orelse unreachable;
        pt = @as(*[1024]u32, @ptrFromInt(pt_virt));

        for (pt) |*e| e.* = 0;
    } else {
        const pt_phys = target_pd[pd_index] & 0xFFFFF000;
        const pt_virt = mapPhysicalPage(pt_phys) orelse unreachable;
        pt = @as(*[1024]u32, @ptrFromInt(pt_virt));
    }

    pt[pt_index] = (phys & 0xFFFFF000) | (flags & 0xFFF);
}

pub fn debugPageDirectory(pd_phys: u32, label: []const u8) void {
    @setRuntimeSafety(false);

    out.print("=== DEBUG PAGE DIRECTORY: ");
    out.print(label);
    out.print(" ===\n");

    out.print("Physical Address: ");
    out.printHex(pd_phys);
    out.print("\n");

    const pd_virt = mapPhysicalPage(pd_phys) orelse {
        out.print("ERROR: Cannot map page directory for debugging!");
        return;
    };

    const pd = @as(*[1024]u32, @ptrFromInt(pd_virt));

    var kernel_entries: u32 = 0;
    out.print("Kernel mappings (768-1023):");
    for (768..1024) |i| {
        if (pd[i] != 0) {
            out.print("  [");
            out.printn(i);
            out.print("] = 0x");
            out.printHex(pd[i]);
            out.print(" (present: ");
            out.println(if ((pd[i] & 1) != 0) "true)" else "false)");
            kernel_entries += 1;
        }
    }
    out.print("Total kernel entries: ");
    out.printn(kernel_entries);
    out.print("\n");

    var user_entries: u32 = 0;
    out.print("User mappings (first 10 non-zero):");
    var count: u32 = 0;
    for (0..768) |i| {
        if (pd[i] != 0 and count < 10) {
            out.print("  [");
            out.printn(i);
            out.print("] = 0x");
            out.printHex(pd[i]);
            out.print(" (present: ");
            out.println(if ((pd[i] & 1) != 0) "true)" else "false)");
            count += 1;
        }
        if (pd[i] != 0) user_entries += 1;
    }
    out.print("Total user entries: ");
    out.printn(user_entries);
    out.println("");

    unmapPhysicalPage(pd_virt);
    out.println("=== END DEBUG ===");
}

pub fn translateInPD(virt: usize, pd: *[1024]u32) ?usize {
    @setRuntimeSafety(false);
    const pd_index = (virt >> 22) & 0x3FF;
    const pt_index = (virt >> 12) & 0x3FF;

    if ((pd[pd_index] & PAGE_PRESENT) == 0) return null;

    const pt_phys = pd[pd_index] & 0xFFFFF000;
    const pt_virt = mapPhysicalPage(pt_phys) orelse return null;
    const pt = @as(*[1024]u32, @ptrFromInt(pt_virt));

    const result = if ((pt[pt_index] & PAGE_PRESENT) == 0) null else {
        const phys_base = pt[pt_index] & 0xFFFFF000;
        const offset = virt & 0xFFF;
        return phys_base + offset;
    };

    unmapPhysicalPage(pt_virt);
    return result;
}
