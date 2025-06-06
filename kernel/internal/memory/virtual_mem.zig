const mem = @import("memory");
const pmm = @import("physical_mem");
const out = @import("output");
pub const PAGE_SIZE = 4096;

pub const PAGE_PRESENT = 1 << 0;
pub const PAGE_RW = 1 << 1;
pub const PAGE_USER = 1 << 2;

pub const USER_SPACE_START: usize = 0x400000;
pub const USER_SPACE_END: usize = 0x80000000;
pub const KERNEL_MEM_BASE: usize = 0xC0000000;
pub const USER_CODE_VADDR: usize = 0x00400000;
pub const USER_STACK_VADDR: usize = 0x7FFFE000;

pub var page_directory: *[1024]u32 = undefined;
pub var page_dir_str: PageDirectory = PageDirectory{
    .physical = 0,
    .virtual = 0,
};

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

    for (768..1024) |i| {
        const pt_kern_physical = pmm.allocPage() orelse unreachable;
        const pt_kern = @as(*[1024]u32, @ptrFromInt(pt_kern_physical));

        for (0..1024) |j| {
            const phys_addr = ((i - 768) << 22) + (j << 12);
            pt_kern[j] = phys_addr | PAGE_PRESENT | PAGE_RW;
        }

        page_directory[i] = pt_kern_physical | PAGE_PRESENT | PAGE_RW;
    }

    page_directory[0] = pt_physical | PAGE_PRESENT | PAGE_RW | PAGE_USER;

    page_dir_str.physical = pd_physical;
    page_dir_str.virtual = pd_physical + KERNEL_MEM_BASE;

    loadPageDirectory(pd_physical);
    enablePaging();

    page_directory = @as(*[1024]u32, @ptrFromInt(pd_physical + KERNEL_MEM_BASE));
}

pub fn mapPage(virt: usize, phys: usize, flags: u32) void {
    @setRuntimeSafety(false);
    const pd_index = (virt >> 22) & 0x3FF;
    const pt_index = (virt >> 12) & 0x3FF;

    var pt: *[1024]u32 = undefined;

    if ((page_directory[pd_index] & PAGE_PRESENT) == 0) {
        const new_pt_phys = pmm.allocPage() orelse unreachable;
        page_directory[pd_index] = new_pt_phys | PAGE_PRESENT | PAGE_RW | PAGE_USER;

        const pt_virt = new_pt_phys + KERNEL_MEM_BASE;
        pt = @as(*[1024]u32, @ptrFromInt(pt_virt));
        for (pt) |*e| e.* = 0;
    } else {
        const pt_phys = page_directory[pd_index] & 0xFFFFF000;
        const pt_virt = pt_phys + KERNEL_MEM_BASE;
        pt = @as(*[1024]u32, @ptrFromInt(pt_virt));
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
    const pt = @as(*[1024]u32, @ptrFromInt(pt_phys + KERNEL_MEM_BASE));

    pt[pt_index] = 0;
    invlpg(virt);
}

pub fn translate(virt: usize) ?usize {
    @setRuntimeSafety(false);
    const pd_index = (virt >> 22) & 0x3FF;
    const pt_index = (virt >> 12) & 0x3FF;

    if ((page_directory[pd_index] & PAGE_PRESENT) == 0) return null;
    const pt_phys = page_directory[pd_index] & 0xFFFFF000;
    const pt = @as(*[1024]u32, @ptrFromInt(pt_phys + KERNEL_MEM_BASE));

    if ((pt[pt_index] & PAGE_PRESENT) == 0) return null;
    const phys_base = pt[pt_index] & 0xFFFFF000;
    const offset = virt & 0xFFF;
    return phys_base + offset;
}

pub fn loadPageDirectory(phys_addr: usize) void {
    @setRuntimeSafety(false);
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

pub fn mapMemory(phys_addr: usize, size: usize) usize {
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

pub fn mapKernelMemory(phys_addr: usize, size: usize) usize {
    if (phys_addr % PAGE_SIZE != 0) return 0;

    const pages_needed = (size + PAGE_SIZE - 1) / PAGE_SIZE;
    const flags = PAGE_PRESENT | PAGE_RW;

    const virt_addr = next_free_virt;

    var i: usize = 0;
    while (i < pages_needed) : (i += 1) {
        mapPage(virt_addr + i * PAGE_SIZE, phys_addr + i * PAGE_SIZE, flags);
    }

    next_free_virt += pages_needed * PAGE_SIZE;

    return virt_addr;
}

pub fn physicalToVirtual(phys: usize) ?usize {
    @setRuntimeSafety(false);

    for (0..1024) |pd_index| {
        if ((page_directory[pd_index] & PAGE_PRESENT) == 0) continue;

        const pt_phys = page_directory[pd_index] & 0xFFFFF000;
        const pt = @as(*[1024]u32, @ptrFromInt(pt_phys + KERNEL_MEM_BASE));

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

pub fn createUserPageDirectory() ?PageDirectory {
    @setRuntimeSafety(false);

    const pd_physical = pmm.allocPage() orelse return null;

    const pd_virtual = pd_physical + KERNEL_MEM_BASE;

    const page_dir: *[1024]u32 = @as(*[1024]u32, @ptrFromInt(pd_virtual));

    for (page_dir) |*entry| entry.* = 0;

    for (768..1024) |i| {
        page_dir[i] = page_directory[i];
    }

    return PageDirectory{
        .physical = pd_physical,
        .virtual = pd_virtual,
    };
}

pub fn mapUserPage(pd: PageDirectory, virt: usize, phys: usize, flags: u32) void {
    @setRuntimeSafety(false);
    const pd_index = (virt >> 22) & 0x3FF;
    const pt_index = (virt >> 12) & 0x3FF;

    const user_page_dir = @as(*[1024]u32, @ptrFromInt(pd.virtual));
    var pt: *[1024]u32 = undefined;

    if ((user_page_dir[pd_index] & PAGE_PRESENT) == 0) {
        const new_pt_phys = pmm.allocPage() orelse unreachable;
        user_page_dir[pd_index] = new_pt_phys | PAGE_PRESENT | PAGE_RW | PAGE_USER;
        pt = @as(*[1024]u32, @ptrFromInt(new_pt_phys + KERNEL_MEM_BASE));
        for (pt) |*e| e.* = 0;
    } else {
        const pt_phys = user_page_dir[pd_index] & 0xFFFFF000;
        pt = @as(*[1024]u32, @ptrFromInt(pt_phys + KERNEL_MEM_BASE));
    }

    pt[pt_index] = (phys & 0xFFFFF000) | (flags & 0xFFF);
    invlpg(virt);
}
