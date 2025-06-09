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

var kernel_heap_base: usize = vmm.KERNEL_MEM_BASE + 0x2000000;
var next_kernel_heap_addr: usize = 0;

pub fn initKernelHeap() bool {
    @setRuntimeSafety(false);
    if (kernel_heap_start != null) return true;

    if (next_kernel_heap_addr == 0) {
        next_kernel_heap_addr = kernel_heap_base;
    }

    const pages_needed = INITIAL_KERNEL_HEAP_SIZE / vmm.PAGE_SIZE;
    var allocated_pages: [64]usize = undefined;
    var i: usize = 0;

    while (i < pages_needed) : (i += 1) {
        const phys = pmm.allocPage() orelse {
            var j: usize = 0;
            while (j < i) : (j += 1) {
                vmm.unmapPage(next_kernel_heap_addr + j * vmm.PAGE_SIZE);
                pmm.freePage(allocated_pages[j]);
            }
            return false;
        };

        allocated_pages[i] = phys;

        vmm.mapPage(next_kernel_heap_addr + i * vmm.PAGE_SIZE, phys, vmm.PAGE_PRESENT | vmm.PAGE_RW);
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

    next_kernel_heap_addr += INITIAL_KERNEL_HEAP_SIZE;

    out.print("Kernel heap initialized at virtual: ");
    out.printHex(@intFromPtr(kernel_heap_start));
    out.print(" size: ");
    out.printHex(kernel_heap_size);
    out.println("");

    return true;
}

fn expandKernelHeap(min_size: usize) bool {
    @setRuntimeSafety(false);

    const expand_size = if (min_size > pmm.PAGE_SIZE)
        ((min_size + pmm.PAGE_SIZE - 1) / pmm.PAGE_SIZE) * pmm.PAGE_SIZE
    else
        pmm.PAGE_SIZE;

    if (next_kernel_heap_addr + expand_size >= vmm.USER_SPACE_START) {
        out.println("Kernel heap expansion would overflow into user space!");
        return false;
    }

    const pages_needed = expand_size / vmm.PAGE_SIZE;
    var allocated_pages: [64]usize = undefined;
    var i: usize = 0;

    while (i < pages_needed) : (i += 1) {
        const phys = pmm.allocPage() orelse {
            var j: usize = 0;
            while (j < i) : (j += 1) {
                vmm.unmapPage(next_kernel_heap_addr + j * vmm.PAGE_SIZE);
                pmm.freePage(allocated_pages[j]);
            }
            return false;
        };

        allocated_pages[i] = phys;
        vmm.mapPage(next_kernel_heap_addr + i * vmm.PAGE_SIZE, phys, vmm.PAGE_PRESENT | vmm.PAGE_RW);
    }

    const new_block = @as(*BlockHeader, @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(next_kernel_heap_addr)))));
    new_block.* = BlockHeader{
        .size = expand_size - @sizeOf(BlockHeader),
        .is_free = true,
        .next = null,
        .prev = null,
    };
    var current = kernel_heap_start;
    while (current != null and current.?.next != null) {
        current = current.?.next;
    }

    if (current != null) {
        current.?.next = new_block;
        new_block.prev = current;

        const current_end = @intFromPtr(current) + @sizeOf(BlockHeader) + current.?.size;
        if (current.?.is_free and current_end == @intFromPtr(new_block)) {
            mergeKernelBlocks(current.?, new_block);
        } else {
            kernel_total_blocks += 1;
            kernel_free_blocks += 1;
        }
    }

    kernel_heap_size += expand_size;
    next_kernel_heap_addr += expand_size;

    out.print("Kernel heap expanded by ");
    out.printHex(expand_size);
    out.print(" bytes to ");
    out.printHex(kernel_heap_size);
    out.println(" total");

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
        const prev_end = @intFromPtr(current.prev) + @sizeOf(BlockHeader) + current.prev.?.size;
        if (prev_end == @intFromPtr(current)) {
            mergeKernelBlocks(current.prev.?, current);
            current = current.prev.?;
        } else {
            break;
        }
    }

    while (current.next != null and current.next.?.is_free) {
        const current_end = @intFromPtr(current) + @sizeOf(BlockHeader) + current.size;
        if (current_end == @intFromPtr(current.next)) {
            mergeKernelBlocks(current, current.next.?);
        } else {
            break;
        }
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

    if (size == 0) {
        out.println("Request for zero size kernel memory");
        return null;
    }

    if (!initKernelHeap()) {
        out.println("Failed to initialize kernel heap");
        return null;
    }

    const aligned_size = (size + 7) & ~@as(usize, 7);

    var block = findKernelFreeBlock(aligned_size);
    if (block == null) {
        if (!expandKernelHeap(aligned_size + @sizeOf(BlockHeader))) {
            out.println("Failed to expand kernel heap");
            return null;
        }
        block = findKernelFreeBlock(aligned_size);
        if (block == null) {
            out.println("Still no suitable kernel block after expansion");
            return null;
        }
    }

    splitBlock(block.?, aligned_size);

    if (block.?.is_free) {
        kernel_free_blocks -= 1;
        kernel_used_blocks += 1;
    }
    block.?.is_free = false;

    const user_data_addr = @intFromPtr(block.?) + @sizeOf(BlockHeader);
    const user_ptr = @as([*]u8, @ptrFromInt(user_data_addr));

    for (0..aligned_size) |i| {
        user_ptr[i] = 0;
    }

    return user_ptr;
}

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

    const ptr_addr = @intFromPtr(ptr);
    if (ptr_addr < @intFromPtr(kernel_heap_start) or ptr_addr >= kernel_heap_end) {
        out.println("Invalid kernel pointer freed!");
        return;
    }

    const block_addr = ptr_addr - @sizeOf(BlockHeader);
    const block = @as(*BlockHeader, @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(block_addr)))));

    if (block.is_free) {
        out.println("Double free detected in kernel heap!");
        return;
    }

    block.is_free = true;
    kernel_used_blocks -= 1;
    kernel_free_blocks += 1;

    coalesceKernelBlocks(block);
}

pub fn freeKernelObject(comptime T: type, obj: *T) void {
    @setRuntimeSafety(false);
    const ptr_addr = @intFromPtr(obj);

    if (ptr_addr < @intFromPtr(kernel_heap_start) or ptr_addr >= kernel_heap_end) {
        out.println("Invalid kernel object freed!");
        return;
    }

    const block_addr = ptr_addr - @sizeOf(BlockHeader);
    const block = @as(*BlockHeader, @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(block_addr)))));

    if (block.is_free) {
        out.println("Double free detected in kernel heap!");
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
    out.print(", end: ");
    out.printHex(kernel_heap_end);
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

    var current = kernel_heap_start;
    var block_count: usize = 0;
    var free_count: usize = 0;
    var used_count: usize = 0;

    out.println("Block list:");
    while (current != null) : (current = current.?.next) {
        out.print("  Block ");
        out.printn(@as(u32, @intCast(block_count)));
        out.print(" at ");
        out.printHex(@intFromPtr(current));
        out.print(" size: ");
        out.printHex(current.?.size);
        out.print(" free: ");
        if (current.?.is_free) {
            out.println("YES");
            free_count += 1;
        } else {
            out.println("NO");
            used_count += 1;
        }
        block_count += 1;

        if (block_count > 100) { // Safety check
            out.println("Too many blocks, stopping iteration");
            break;
        }
    }

    out.print("Counted blocks: ");
    out.printn(@as(u32, @intCast(block_count)));
    out.print(" (free: ");
    out.printn(@as(u32, @intCast(free_count)));
    out.print(", used: ");
    out.printn(@as(u32, @intCast(used_count)));
    out.println(")");
}

pub fn verifyKernelHeapMapping() bool {
    @setRuntimeSafety(false);

    if (kernel_heap_start == null) {
        out.println("Kernel heap not initialized");
        return false;
    }

    out.println("=== Kernel Heap Mapping Verification ===");

    const heap_start_virt = @intFromPtr(kernel_heap_start);
    const heap_start_phys = vmm.translate(heap_start_virt);

    if (heap_start_phys) |phys| {
        out.print("Heap start mapping OK: ");
        out.printHex(heap_start_virt);
        out.print(" -> ");
        out.printHex(phys);
        out.println("");
    } else {
        out.print("ERROR: Heap start not mapped at ");
        out.printHex(heap_start_virt);
        out.println("");
        return false;
    }

    const pages_to_check = kernel_heap_size / vmm.PAGE_SIZE;
    var i: usize = 0;
    while (i < pages_to_check) : (i += 1) {
        const virt = heap_start_virt + i * vmm.PAGE_SIZE;
        const phys = vmm.translate(virt);

        if (phys == null) {
            out.print("ERROR: Heap page not mapped at ");
            out.printHex(virt);
            out.print(" (page ");
            out.printn(@as(u32, @intCast(i)));
            out.println(")");
            return false;
        }
    }

    out.print("All ");
    out.printn(@as(u32, @intCast(pages_to_check)));
    out.println(" kernel heap pages are properly mapped");
    return true;
}
