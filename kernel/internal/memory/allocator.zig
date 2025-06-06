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

var heap_start: ?*BlockHeader = null;
var heap_end: usize = 0;
var heap_size: usize = 0;
var free_blocks: usize = 0;
var used_blocks: usize = 0;
var total_blocks: usize = 0;
const INITIAL_HEAP_SIZE = 16 * pmm.PAGE_SIZE;
const MIN_BLOCK_SIZE = 16;

pub fn initHeap() bool {
    @setRuntimeSafety(false);
    if (heap_start != null) return true;

    const heap_addr = vmm.allocVirtual(
        INITIAL_HEAP_SIZE,
        vmm.PAGE_PRESENT | vmm.PAGE_RW,
    ) orelse return false;

    heap_start = @as(*BlockHeader, @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(heap_addr)))));
    heap_size = INITIAL_HEAP_SIZE;
    heap_end = heap_addr + heap_size;

    heap_start.?.* = BlockHeader{
        .size = heap_size - @sizeOf(BlockHeader),
        .is_free = true,
        .next = null,
        .prev = null,
    };

    total_blocks = 1;
    free_blocks = 1;
    used_blocks = 0;

    return true;
}

fn expandHeap(min_size: usize) bool {
    @setRuntimeSafety(false);
    const expand_size = if (min_size > pmm.PAGE_SIZE)
        ((min_size + pmm.PAGE_SIZE - 1) / pmm.PAGE_SIZE) * pmm.PAGE_SIZE
    else
        pmm.PAGE_SIZE;

    const new_addr = vmm.allocVirtual(
        expand_size,
        vmm.PAGE_PRESENT | vmm.PAGE_RW,
    ) orelse return false;

    const new_block = @as(*BlockHeader, @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(new_addr)))));
    new_block.* = BlockHeader{
        .size = expand_size - @sizeOf(BlockHeader),
        .is_free = true,
        .next = null,
        .prev = null,
    };

    var current = heap_start;
    while (current != null and current.?.next != null) {
        current = current.?.next;
    }

    if (current != null) {
        current.?.next = new_block;
        new_block.prev = current;

        if (current.?.is_free) {
            mergeBlocks(current.?, new_block);
        } else {
            total_blocks += 1;
            free_blocks += 1;
        }
    } else {
        total_blocks += 1;
        free_blocks += 1;
    }

    heap_size += expand_size;
    heap_end += expand_size;
    return true;
}

fn findFreeBlock(size: usize) ?*BlockHeader {
    @setRuntimeSafety(false);
    var current = heap_start;

    while (current != null) : (current = current.?.next) {
        if (current.?.is_free and current.?.size >= size) {
            return current;
        }
    }

    return null;
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

        total_blocks += 1;
        free_blocks += 1;
    }
}

fn mergeBlocks(first: *BlockHeader, second: *BlockHeader) void {
    @setRuntimeSafety(false);
    first.size += second.size + @sizeOf(BlockHeader);
    first.next = second.next;

    if (second.next != null) {
        second.next.?.prev = first;
    }

    total_blocks -= 1;
    if (second.is_free) {
        free_blocks -= 1;
    } else {
        used_blocks -= 1;
    }
}

fn coalesceBlocks(mut_block: *BlockHeader) void {
    @setRuntimeSafety(false);

    var current = mut_block;

    while (current.prev != null and current.prev.?.is_free) {
        current = current.prev.?;
    }

    while (current.next != null and current.next.?.is_free) {
        mergeBlocks(current, current.next.?);
    }
}

pub fn request(size: usize) ?[*]u8 {
    @setRuntimeSafety(false);

    if (size == 0) return null;

    if (!initHeap()) {
        out.print("Failed to initialize heap\n");
        return null;
    }

    const aligned_size = (size + 7) & ~@as(usize, 7);

    var block = findFreeBlock(aligned_size);
    if (block == null) {
        if (!expandHeap(aligned_size + @sizeOf(BlockHeader))) {
            out.print("Failed to expand heap\n");
            return null;
        }
        block = findFreeBlock(aligned_size);
        if (block == null) {
            out.print("Still no suitable block after expansion\n");
            return null;
        }
    }

    splitBlock(block.?, aligned_size);

    if (block.?.is_free) {
        free_blocks -= 1;
        used_blocks += 1;
    }
    block.?.is_free = false;

    const user_data_addr = @intFromPtr(block.?) + @sizeOf(BlockHeader);

    const user_ptr = @as([*]u8, @ptrFromInt(user_data_addr));
    for (0..aligned_size) |i| {
        user_ptr[i] = 0;
    }

    return user_ptr;
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

    if (heap_start == null) return;

    const block_addr = @intFromPtr(ptr) - @sizeOf(BlockHeader);
    const block = @as(*BlockHeader, @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(block_addr)))));

    if (block.is_free) {
        return;
    }

    block.is_free = true;
    used_blocks -= 1;
    free_blocks += 1;

    coalesceBlocks(block);
}

pub fn freeObject(comptime T: type, obj: *T) void {
    @setRuntimeSafety(false);
    const block_addr = @intFromPtr(obj) - @sizeOf(BlockHeader);
    const block = @as(*BlockHeader, @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(block_addr)))));

    if (block.is_free) {
        return;
    }

    block.is_free = true;
    used_blocks -= 1;
    free_blocks += 1;

    coalesceBlocks(block);
}

pub fn duplicate(comptime T: type, original: []const T) ?[*]T {
    @setRuntimeSafety(false);
    const size = @sizeOf(T) * original.len;
    const ptr = request(size) orelse {
        sys.panic("Failed to allocate memory for duplicate");
    };

    const dest: [*]u8 = @alignCast(@ptrCast(ptr));
    for (0..original.len) |i| {
        dest[i] = original[i];
    }

    return dest;
}

pub fn duplicateObject(comptime T: type, original: T) ?*T {
    @setRuntimeSafety(false);
    const size = @sizeOf(T);
    const ptr = request(size) orelse {
        sys.panic("Failed to allocate memory for object duplicate");
    };

    const dest: *T = @alignCast(@ptrCast(ptr));
    dest.* = original;

    return dest;
}

pub fn debugHeap() void {
    @setRuntimeSafety(false);
    out.println("=== Heap Memory ===");
    out.print("Heap start: ");
    out.printHex(@intFromPtr(heap_start));
    out.print(", size: ");
    out.printHex(heap_size);
    out.println("");

    out.print("Total blocks: ");
    out.printn(total_blocks);
    out.println("");
    out.print("Free blocks: ");
    out.printn(free_blocks);
    out.println("");
    out.print("Used blocks: ");
    out.printn(used_blocks);
    out.println("");
}
