const multiboot2 = @import("multiboot2");
const mem = @import("memory");
const out = @import("output");
const pmm = @import("physical_mem");
const sys = @import("system");

pub const PAGE_SIZE: usize = 4096;
pub const ENTRIES_PER_PAGE_TABLE: usize = 1024;
pub const PAGE_DIR_INDEX_SHIFT: u5 = 22;
pub const PAGE_TABLE_INDEX_SHIFT: u5 = 12;
pub const PAGE_DIR_INDEX_MASK: u32 = 0x3FF;
pub const PAGE_TABLE_INDEX_MASK: u32 = 0x3FF;

pub const PAGE_PRESENT: u32 = 1 << 0;
pub const PAGE_WRITABLE: u32 = 1 << 1;
pub const PAGE_USER: u32 = 1 << 2;
pub const PAGE_WRITE_THROUGH: u32 = 1 << 3;
pub const PAGE_CACHE_DISABLE: u32 = 1 << 4;
pub const PAGE_ACCESSED: u32 = 1 << 5;
pub const PAGE_DIRTY: u32 = 1 << 6;
pub const PAGE_SIZE_4MB: u32 = 1 << 7;
pub const PAGE_GLOBAL: u32 = 1 << 8;

pub const PageDirEntry = u32;
pub const PageTableEntry = u32;

pub const PageDirectory = struct {
    entries: [ENTRIES_PER_PAGE_TABLE]PageDirEntry align(PAGE_SIZE),
};

pub const PageTable = struct {
    entries: [ENTRIES_PER_PAGE_TABLE]PageTableEntry align(PAGE_SIZE),
};

var kernel_page_directory: *PageDirectory = undefined;
var kernel_page_directory_phys: u32 = undefined;

var kernelStart: u32 = undefined;
var kernelEnd: u32 = undefined;

pub fn init(kernelStartFn: u32, kernelEndFn: u32) void {
    kernelStart = kernelStartFn;
    kernelEnd = kernelEndFn;
    @setRuntimeSafety(false);
    const page_dir_addr = pmm.allocPage() orelse {
        out.print("Failed to allocate memory for page directory\n");
        return;
    };
    kernel_page_directory_phys = @as(u32, @intCast(page_dir_addr));
    kernel_page_directory = @ptrFromInt(page_dir_addr);

    for (0..ENTRIES_PER_PAGE_TABLE) |i| {
        kernel_page_directory.entries[i] = 0;
    }

    _ = mapPages(0, 0, 1024, PAGE_PRESENT | PAGE_WRITABLE);

    enablePaging();
}

inline fn getPageDirIndex(virt_addr: u32) usize {
    @setRuntimeSafety(false);
    return @intCast((virt_addr >> PAGE_DIR_INDEX_SHIFT) & PAGE_DIR_INDEX_MASK);
}

inline fn getPageTableIndex(virt_addr: u32) usize {
    @setRuntimeSafety(false);
    return @intCast((virt_addr >> PAGE_TABLE_INDEX_SHIFT) & PAGE_TABLE_INDEX_MASK);
}

fn getOrCreatePageTable(dir_index: usize, flags: u32) ?*PageTable {
    @setRuntimeSafety(false);
    const entry = kernel_page_directory.entries[dir_index];

    if ((entry & PAGE_PRESENT) != 0) {
        return @as(*PageTable, @ptrFromInt(entry & ~@as(u32, 0xFFF)));
    } else {
        const page_table_addr = pmm.allocPage() orelse {
            out.print("Failed to allocate page for page table\n");
            return null;
        };

        const page_table = @as(*PageTable, @ptrFromInt(page_table_addr));

        for (0..ENTRIES_PER_PAGE_TABLE) |i| {
            page_table.entries[i] = 0;
        }

        kernel_page_directory.entries[dir_index] = @as(u32, @intCast(page_table_addr)) | (flags | PAGE_PRESENT | PAGE_WRITABLE);

        return page_table;
    }
}

pub fn mapPage(virt_addr: u32, phys_addr: u32, flags: u32) ?void {
    @setRuntimeSafety(false);
    const dir_index = getPageDirIndex(virt_addr);
    const table_index = getPageTableIndex(virt_addr);

    var actual_flags = flags;
    if (actual_flags <= kernelEnd and actual_flags >= kernelStart) {
        sys.panic("Cannot map page in kernel space");
        return null;
    } else {
        actual_flags |= PAGE_PRESENT | PAGE_WRITABLE;
        actual_flags &= ~PAGE_USER;
    }

    const page_table = getOrCreatePageTable(dir_index, PAGE_PRESENT | PAGE_WRITABLE).?;

    if ((page_table.entries[table_index] & PAGE_PRESENT) != 0) {
        return null;
    }

    page_table.entries[table_index] = (phys_addr & ~@as(u32, 0xFFF)) | actual_flags;

    invalidatePage(virt_addr);
    return {};
}

pub fn mapPages(virt_addr: u32, phys_addr: u32, count: usize, flags: u32) bool {
    @setRuntimeSafety(false);
    var i: usize = 0;
    var vaddr = virt_addr;
    var paddr = phys_addr;

    while (i < count) : (i += 1) {
        mapPage(vaddr, paddr, flags) orelse {
            sys.panic("Failed to map page\n");
            return false;
        };

        vaddr += PAGE_SIZE;
        paddr += PAGE_SIZE;
    }

    return true;
}

pub fn unmapPage(virt_addr: u32) void {
    @setRuntimeSafety(false);
    const dir_index = getPageDirIndex(virt_addr);
    const table_index = getPageTableIndex(virt_addr);

    if ((kernel_page_directory.entries[dir_index] & PAGE_PRESENT) == 0) {
        return; // Nothing to unmap
    }

    const page_table = @as(*PageTable, @ptrFromInt(kernel_page_directory.entries[dir_index] & ~@as(u32, 0xFFF)));

    page_table.entries[table_index] = 0;

    invalidatePage(virt_addr);
}

pub fn getPhysicalAddress(virt_addr: u32) ?u32 {
    @setRuntimeSafety(false);
    const dir_index = getPageDirIndex(virt_addr);
    const table_index = getPageTableIndex(virt_addr);
    const offset = virt_addr & 0xFFF;

    if ((kernel_page_directory.entries[dir_index] & PAGE_PRESENT) == 0) {
        return null;
    }

    const page_table = @as(*PageTable, @ptrFromInt(kernel_page_directory.entries[dir_index] & ~@as(u32, 0xFFF)));

    if ((page_table.entries[table_index] & PAGE_PRESENT) == 0) {
        return null;
    }

    const phys_addr = (page_table.entries[table_index] & ~@as(u32, 0xFFF)) + offset;
    return phys_addr;
}

pub inline fn invalidatePage(addr: u32) void {
    @setRuntimeSafety(false);
    asm volatile ("invlpg (%[addr])"
        :
        : [addr] "r" (addr),
        : "memory"
    );
}

pub fn enablePaging() void {
    @setRuntimeSafety(false);
    const page_dir_phys = kernel_page_directory_phys;
    asm volatile ("mov %[page_dir], %%cr3"
        :
        : [page_dir] "r" (page_dir_phys),
    );

    asm volatile (
        \\mov %%cr0, %%eax
        \\or $0x80000000, %%eax
        \\mov %%eax, %%cr0
        ::: "eax", "memory");
}

pub fn allocateVirtualMemory(size: usize, flags: u32) ?u32 {
    @setRuntimeSafety(false);

    // Calculate needed pages
    const pages_needed = (size + PAGE_SIZE - 1) / PAGE_SIZE;

    out.print("Allocating 0x");
    out.printHex(@intCast(size));
    out.print(" bytes, need 0x");
    out.printHex(@intCast(pages_needed));
    out.print(" pages. ");
    out.print("Kernel Start is 0x");
    out.printHex(kernelStart);
    out.print(", Kernel End is 0x");
    out.printHex(kernelEnd);
    out.print("\n");

    // Start allocation right after kernel end, aligned to page boundary
    var start_addr = (kernelEnd + PAGE_SIZE - 1) & ~@as(u32, PAGE_SIZE - 1);

    // Add a safety buffer of a few pages after the kernel
    start_addr += PAGE_SIZE * 8; // 8 page (32KB) safety buffer

    out.print("Starting allocation search at 0x");
    out.printHex(start_addr);
    out.print("\n");

    // Find a free region
    var found = false;
    var virt_addr = start_addr;

    while (virt_addr < 0xF0000000 and !found) {
        found = true;

        // Check if each page in this potential region is free
        for (0..pages_needed) |i| {
            const check_addr = virt_addr + @as(u32, @intCast(i * PAGE_SIZE));

            // Check if this address is already mapped
            if (isPageMapped(check_addr)) {
                found = false;
                virt_addr += PAGE_SIZE; // Move to next page and try again
                break;
            }
        }
    }

    if (!found) {
        out.print("Failed to find a free virtual memory region\n");
        return null;
    }

    out.print("Found free region at 0x");
    out.printHex(virt_addr);
    out.print("\n");

    for (0..pages_needed) |i| {
        const curr_addr = virt_addr + @as(u32, @intCast(i * PAGE_SIZE));

        const phys_addr = pmm.allocPage() orelse {
            out.print("Failed to allocate physical page\n");

            for (0..i) |j| {
                const addr_to_free = virt_addr + @as(u32, @intCast(j * PAGE_SIZE));
                if (getPhysicalAddress(addr_to_free)) |phys| {
                    unmapPage(addr_to_free);
                    pmm.freePage(phys);
                }
            }

            return null;
        };

        if (!mapPageDirect(curr_addr, @intCast(phys_addr), flags)) {
            out.print("Failed to map page at 0x");
            out.printHex(curr_addr);
            out.print("\n");

            pmm.freePage(phys_addr);

            for (0..i) |j| {
                const addr_to_free = virt_addr + @as(u32, @intCast(j * PAGE_SIZE));
                if (getPhysicalAddress(addr_to_free)) |phys| {
                    unmapPage(addr_to_free);
                    pmm.freePage(phys);
                }
            }

            return null;
        }

        out.print("Mapped virtual 0x");
        out.printHex(curr_addr);
        out.print(" to physical 0x");
        out.printHex(@intCast(phys_addr));
        out.print("\n");
    }

    out.print("Successfully allocated ");
    out.printn(pages_needed);
    out.print(" pages at 0x");
    out.printHex(virt_addr);
    out.print("\n");

    return virt_addr;
}

fn isPageMapped(virt_addr: u32) bool {
    @setRuntimeSafety(false);

    const dir_index = getPageDirIndex(virt_addr);

    if ((kernel_page_directory.entries[dir_index] & PAGE_PRESENT) == 0) {
        return false;
    }

    const page_table = @as(*PageTable, @ptrFromInt(kernel_page_directory.entries[dir_index] & ~@as(u32, 0xFFF)));
    const table_index = getPageTableIndex(virt_addr);

    return (page_table.entries[table_index] & PAGE_PRESENT) != 0;
}

fn mapPageDirect(virt_addr: u32, phys_addr: u32, flags: u32) bool {
    @setRuntimeSafety(false);

    const dir_index = getPageDirIndex(virt_addr);
    const table_index = getPageTableIndex(virt_addr);

    if ((kernel_page_directory.entries[dir_index] & PAGE_PRESENT) == 0) {
        const page_table_addr = pmm.allocPage() orelse {
            out.print("Failed to allocate page for page table\n");
            return false;
        };

        const page_table = @as(*PageTable, @ptrFromInt(page_table_addr));
        for (0..ENTRIES_PER_PAGE_TABLE) |i| {
            page_table.entries[i] = 0;
        }

        kernel_page_directory.entries[dir_index] = @as(u32, @intCast(page_table_addr)) | PAGE_PRESENT | PAGE_WRITABLE;

        out.print("Created new page table at directory index ");
        out.printn(dir_index);
        out.print("\n");
    }

    const page_table = @as(*PageTable, @ptrFromInt(kernel_page_directory.entries[dir_index] & ~@as(u32, 0xFFF)));

    if ((page_table.entries[table_index] & PAGE_PRESENT) != 0) {
        out.print("Page at virtual address 0x");
        out.printHex(virt_addr);
        out.print(" is already mapped\n");
        return false;
    }

    page_table.entries[table_index] = (phys_addr & ~@as(u32, 0xFFF)) | flags | PAGE_PRESENT;

    invalidatePage(virt_addr);

    return true;
}

pub fn freeVirtualMemory(virt_addr: u32, size: usize) void {
    @setRuntimeSafety(false);
    const pages = (size + PAGE_SIZE - 1) / PAGE_SIZE;

    var i: usize = 0;
    while (i < pages) : (i += 1) {
        const addr = virt_addr + @as(u32, @intCast(i * PAGE_SIZE));
        if (getPhysicalAddress(addr)) |phys_addr| {
            unmapPage(addr);
            pmm.freePage(phys_addr);
        }
    }
}

pub fn pageFaultHandler(_: u32, _: u32) void {
    out.print("Page fault at address with error code\n");

    while (true) {
        asm volatile ("hlt");
    }
}
