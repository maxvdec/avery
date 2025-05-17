const vmm = @import("virtual_mem");
const pmm = @import("physical_mem");
const out = @import("output");
const sys = @import("system");
const mem = @import("memory");

const BlockHeader = packed struct {
    size: u32,
    isFree: bool,
    magic: u16,
    prev: ?*BlockHeader,
    next: ?*BlockHeader,
};

const BLOCK_MAGIC: u16 = 0xBEAD; // Magic number to identify blocks
const MIN_BLOCK_SIZE: usize = 16;
const HEADER_SIZE: usize = @sizeOf(BlockHeader);

var heap_start: usize = undefined;
var heap_end: usize = undefined;
var heap_size: usize = 0;
var first_block: *volatile BlockHeader = undefined;
var initialized: bool = false;

pub fn init(initial_size: usize) void {
    @setRuntimeSafety(false);
    if (initialized) {
        return;
    }

    const size = @max(initial_size, 64 * 1024); // Minimum heap size
    const pages_needed = (size + vmm.PAGE_SIZE - 1) / vmm.PAGE_SIZE;
    const aligned_size = pages_needed * vmm.PAGE_SIZE;

    out.print("Allocating heap of size: ");
    out.printHex(@intCast(aligned_size));
    out.print("\n");

    const addr_opt = vmm.allocateVirtualMemory(aligned_size, vmm.PAGE_PRESENT | vmm.PAGE_WRITABLE);
    if (addr_opt == null) {
        out.print("Failed to allocate virtual memory for heap\n");
        sys.panic("Heap allocation failed");
    }

    const addr = @as(usize, @intCast(addr_opt.?));

    heap_start = addr;
    heap_end = addr + aligned_size;
    heap_size = aligned_size;

    first_block = @ptrFromInt(addr);
    first_block.* = BlockHeader{
        .size = @as(u32, @intCast(aligned_size - HEADER_SIZE)),
        .isFree = true,
        .magic = BLOCK_MAGIC,
        .prev = null,
        .next = null,
    };

    initialized = true;

    out.print("Heap initialized successfully\n");
}
