const vmm = @import("virtual_mem");
const pmm = @import("physical_mem");
const out = @import("output");
const sys = @import("system");
const mem = @import("memory");

const BlockHeader = struct {
    size: usize,
    is_free: bool,
    next: ?*BlockHeader,
    prev: ?*BlockHeader,
};

var kernel_heap_start: ?*BlockHeader = null;
var kernel_heap_end: usize = 0;
var kernel_heap_size: usize = 0;
var kernel_free_blocks: usize = 0;
var kernel_used_blocks: usize = 0;
var kernel_total_blocks: usize = 0;
const INITIAL_KERNEL_HEAP_SIZE = 8 * pmm.PAGE_SIZE;
const MIN_BLOCK_SIZE = 16;

var next_kernel_heap_addr: usize = vmm.KERNEL_MEM_BASE + 0x1000000; // Start after initial kernel mappings

pub fn initKernelHeap() bool {
    @setRuntimeSafety(false);
    if (kernel_heap_start != null) return true;

    // Allocate physical pages for kernel heap
    const pages_needed = INITIAL_KERNEL_HEAP_SIZE / vmm.PAGE_SIZE;
    var i: usize = 0;
    while (i < pages_needed) : (i += 1) {
        const phys = pmm.allocPage() orelse {
            // Cleanup on failure
            var j: usize = 0;
            while (j < i) : (j += 1) {
                vmm.unmapPage(next_kernel_heap_addr + j * vmm.PAGE_SIZE);
            }
            return false;
        };

        // Map physical page to kernel virtual address
        vmm.mapPage(next_kernel_heap_addr + i * vmm.PAGE_SIZE, phys, vmm.PAGE_PRESENT | vmm.PAGE_RW // No PAGE_USER for kernel space
        );
    }

    kernel_heap_start = @as(*BlockHeader, @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(next_kernel_heap_addr)))));
    kernel_heap_size = INITIAL_KERNEL_HEAP_SIZE;
    kernel_heap_end = next_kernel_heap_addr + kernel_heap_size;

    kernel_heap_start.?.* = BlockHeader{
        .size = kernel_heap_size - @sizeOf(BlockHeader),
        .is_free = true,
        .next = null,
        .prev = null,
    };

    kernel_total_blocks = 1;
    kernel_free_blocks = 1;
    kernel_used_blocks = 0;

    // Update next available kernel address
    next_kernel_heap_addr += INITIAL_KERNEL_HEAP_SIZE;

    return true;
}

fn expandKernelHeap(min_size: usize) bool {
    @setRuntimeSafety(false);
    const expand_size = if (min_size > pmm.PAGE_SIZE)
        ((min_size + pmm.PAGE_SIZE - 1) / pmm.PAGE_SIZE) * pmm.PAGE_SIZE
    else
        pmm.PAGE_SIZE;

    // Allocate and map physical pages to kernel virtual space
    const pages_needed = expand_size / vmm.PAGE_SIZE;
    var i: usize = 0;
    while (i < pages_needed) : (i += 1) {
        const phys = pmm.allocPage() orelse {
            // Cleanup on failure
            var j: usize = 0;
            while (j < i) : (j += 1) {
                vmm.unmapPage(next_kernel_heap_addr + j * vmm.PAGE_SIZE);
            }
            return false;
        };

        vmm.mapPage(next_kernel_heap_addr + i * vmm.PAGE_SIZE, phys, vmm.PAGE_PRESENT | vmm.PAGE_RW);
    }

    const new_block = @as(*BlockHeader, @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(next_kernel_heap_addr)))));
    new_block.* = BlockHeader{
        .size = expand_size - @sizeOf(BlockHeader),
        .is_free = true,
        .next = null,
        .prev = null,
    };

    // Link to existing kernel heap
    var current = kernel_heap_start;
    while (current != null and current.?.next != null) {
        current = current.?.next;
    }

    if (current != null) {
        current.?.next = new_block;
        new_block.prev = current;

        if (current.?.is_free) {
            mergeKernelBlocks(current.?, new_block);
        } else {
            kernel_total_blocks += 1;
            kernel_free_blocks += 1;
        }
    }

    kernel_heap_size += expand_size;
    next_kernel_heap_addr += expand_size;
    return true;
}

fn findKernelFreeBlock(size: usize) ?*BlockHeader {
    @setRuntimeSafety(false);
    var current = kernel_heap_start;

    while (current != null) : (current = current.?.next) {
        if (current.?.is_free and current.?.size >= size) {
            return current;
        }
    }

    return null;
}

fn mergeKernelBlocks(first: *BlockHeader, second: *BlockHeader) void {
    @setRuntimeSafety(false);
    first.size += second.size + @sizeOf(BlockHeader);
    first.next = second.next;

    if (second.next != null) {
        second.next.?.prev = first;
    }

    kernel_total_blocks -= 1;
    if (second.is_free) {
        kernel_free_blocks -= 1;
    } else {
        kernel_used_blocks -= 1;
    }
}

fn coalesceKernelBlocks(mut_block: *BlockHeader) void {
    @setRuntimeSafety(false);

    var current = mut_block;

    while (current.prev != null and current.prev.?.is_free) {
        current = current.prev.?;
    }

    while (current.next != null and current.next.?.is_free) {
        mergeKernelBlocks(current, current.next.?);
    }
}

fn splitBlock(block: *BlockHeader, size: usize) void {
    @setRuntimeSafety(false);
    const remaining_size = block.size - size - @sizeOf(BlockHeader);

    if (remaining_size >= MIN_BLOCK_SIZE) {
        const new_block_addr = @intFromPtr(block) + @sizeOf(BlockHeader) + size;
        const new_block = @as(*BlockHeader, @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(new_block_addr)))));

        new_block.* = BlockHeader{
            .size = remaining_size,
            .is_free = true,
            .next = block.next,
            .prev = block,
        };

        if (block.next != null) {
            block.next.?.prev = new_block;
        }

        block.next = new_block;
        block.size = size;

        kernel_total_blocks += 1;
        kernel_free_blocks += 1;
    }
}

pub fn requestKernel(size: usize) ?[*]u8 {
    @setRuntimeSafety(false);

    if (size == 0) return null;

    if (!initKernelHeap()) {
        out.print("Failed to initialize kernel heap\n");
        return null;
    }

    const aligned_size = (size + 7) & ~@as(usize, 7);

    var block = findKernelFreeBlock(aligned_size);
    if (block == null) {
        if (!expandKernelHeap(aligned_size + @sizeOf(BlockHeader))) {
            out.print("Failed to expand kernel heap\n");
            return null;
        }
        block = findKernelFreeBlock(aligned_size);
        if (block == null) {
            out.print("Still no suitable kernel block after expansion\n");
            return null;
        }
    }

    splitBlock(block.?, aligned_size); // Reuse existing splitBlock function

    if (block.?.is_free) {
        kernel_free_blocks -= 1;
        kernel_used_blocks += 1;
    }
    block.?.is_free = false;

    const user_data_addr = @intFromPtr(block.?) + @sizeOf(BlockHeader);
    const user_ptr = @as([*]u8, @ptrFromInt(user_data_addr));

    // Zero initialize
    for (0..aligned_size) |i| {
        user_ptr[i] = 0;
    }

    return user_ptr;
}

// Kernel-specific object allocation functions
pub fn storeKernel(comptime T: type) *T {
    @setRuntimeSafety(false);
    const size = @sizeOf(T);
    const ptr = requestKernel(size) orelse {
        sys.panic("Failed to allocate kernel memory for object");
    };

    return @alignCast(@ptrCast(ptr));
}

pub fn storeManyKernel(comptime T: type, count: usize) [*]T {
    @setRuntimeSafety(false);
    const size = @sizeOf(T) * count;
    const ptr = requestKernel(size) orelse {
        sys.panic("Failed to allocate kernel memory for array");
    };
    return @alignCast(@ptrCast(ptr));
}

pub fn freeKernel(ptr: [*]u8) void {
    @setRuntimeSafety(false);

    if (kernel_heap_start == null) return;

    const block_addr = @intFromPtr(ptr) - @sizeOf(BlockHeader);
    const block = @as(*BlockHeader, @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(block_addr)))));

    if (block.is_free) {
        return;
    }

    block.is_free = true;
    kernel_used_blocks -= 1;
    kernel_free_blocks += 1;

    coalesceKernelBlocks(block);
}

pub fn freeKernelObject(comptime T: type, obj: *T) void {
    @setRuntimeSafety(false);
    const block_addr = @intFromPtr(obj) - @sizeOf(BlockHeader);
    const block = @as(*BlockHeader, @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(block_addr)))));

    if (block.is_free) {
        return;
    }

    block.is_free = true;
    kernel_used_blocks -= 1;
    kernel_free_blocks += 1;

    coalesceKernelBlocks(block);
}

pub fn debugKernelHeap() void {
    @setRuntimeSafety(false);
    out.println("=== Kernel Heap Memory ===");
    out.print("Kernel heap start: ");
    out.printHex(@intFromPtr(kernel_heap_start));
    out.print(", size: ");
    out.printHex(kernel_heap_size);
    out.println("");

    out.print("Total kernel blocks: ");
    out.printn(kernel_total_blocks);
    out.println("");
    out.print("Free kernel blocks: ");
    out.printn(kernel_free_blocks);
    out.println("");
    out.print("Used kernel blocks: ");
    out.printn(kernel_used_blocks);
    out.println("");
}
