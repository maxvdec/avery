const alloc = @import("allocator");
const kalloc = @import("kern_allocator");
const str = @import("string");
const sys = @import("system");
const out = @import("output");

extern fn memcpy(dest: [*]u8, src: [*]const u8, len: usize) [*]u8;

pub fn copy(comptime T: type, dest: [*]T, src: [*]const T, count: usize) void {
    @setRuntimeSafety(false);
    if (count == 0) return;
    const size = @sizeOf(T);
    const src_bytes = @as([*]const u8, @ptrCast(src));
    const dest_bytes = @as([*]u8, @ptrCast(dest));
    _ = memcpy(dest_bytes, src_bytes, count * size);
}

pub fn copyBytes(dest: [*]u8, src: []const u8) void {
    for (0..src.len) |i| {
        dest[i] = src[i];
    }
}

pub fn Pointer(comptime T: type) type {
    return struct {
        data: [*]T,

        const Self = @This();

        pub fn init(data: [*]T) Self {
            return Self{ .data = data };
        }

        pub fn atAddr(addr: usize) Self {
            const data: [*]T = @ptrFromInt(addr);
            return Self{ .data = data };
        }

        pub fn castValue(self: Self, comptime Y: type, index: usize) [*]Y {
            return @as([*]Y, @ptrCast(self.offsetPtr(index)));
        }

        pub fn castPtr(self: Self, comptime Y: type, index: usize) Pointer(Y) {
            const new_ptr = @as([*]Y, @ptrCast(self.offsetPtr(index)));
            return Pointer(Y){ .data = new_ptr };
        }

        pub fn get(self: Self, index: usize) *T {
            return &self.data[index];
        }

        pub fn dereference(self: Self, index: usize) T {
            return self.data[index];
        }

        pub fn set(self: Self, index: usize, value: T) void {
            self.data[index] = value;
        }

        pub fn from(ptr: *anyopaque) Self {
            const rawPtr: [*]T = @ptrCast(ptr);
            return Self{ .data = rawPtr };
        }

        pub fn offset(self: Self, count: usize) Self {
            const new_ptr: [*]T = @ptrCast(&self.data[count]);
            return Self{
                .data = new_ptr,
            };
        }

        pub fn offsetPtr(self: Self, count: usize) [*]T {
            return self.data + count;
        }

        pub fn toSlice(self: Self, len: usize) []T {
            return self.data[0..len];
        }

        pub fn point(_: Self, addr: u32) Self {
            const data: [*]T = @ptrFromInt(addr);
            return Self{ .data = data };
        }
    };
}

pub fn VolatilePointer(comptime T: type) type {
    return struct {
        data: [*]volatile T,

        const Self = @This();

        pub fn init(data: [*]T) Self {
            return Self{ .data = data };
        }

        pub fn castValue(self: Self, comptime Y: type, index: usize) [*]Y {
            return @as([*]u8, @ptrCast(self.offsetPtr(index)));
        }

        pub fn atAddr(addr: usize) Self {
            const data: [*]T = @ptrFromInt(addr);
            return Self{ .data = data };
        }

        pub fn castPtr(self: Self, comptime Y: type, index: usize) VolatilePointer(Y) {
            const new_ptr = @as([*]volatile Y, @ptrCast(self.offsetPtr(index)));
            return VolatilePointer(Y){ .data = new_ptr };
        }

        pub fn get(self: Self, index: usize) *volatile T {
            return &self.data[index];
        }

        pub fn from(ptr: *anyopaque) Self {
            const rawPtr: [*]volatile T = @ptrCast(ptr);
            return Self{ .data = rawPtr };
        }

        pub fn dereference(self: Self, index: usize) T {
            return self.data[index];
        }

        pub fn set(self: Self, index: usize, value: T) void {
            self.data[index] = value;
        }

        pub fn offset(self: Self, count: usize) Self {
            return Self{
                .data = self.data + count,
            };
        }

        pub fn offsetPtr(self: Self, count: usize) [*]volatile T {
            return self.data + count;
        }

        pub fn toSlice(self: Self, len: usize) []volatile T {
            return self.data[0..len];
        }

        pub fn point(_: Self, addr: u32) Self {
            const data: [*]T = @ptrFromInt(addr);
            return Self{ .data = data };
        }
    };
}

pub fn alignUp(addr: usize, alignment: usize) usize {
    return (addr + alignment - 1) & ~(alignment - 1);
}

pub fn alignDown(addr: usize, alignment: usize) usize {
    return addr & ~(alignment - 1);
}

pub fn Tuple(comptime T: type, comptime U: type) type {
    return struct {
        a: T,
        b: U,

        const Self = @This();

        pub fn init(a: T, b: U) Self {
            return Self{ .a = a, .b = b };
        }

        pub fn getForType(self: Self, comptime Y: type) ?Y {
            if (@typeInfo(T) == @typeInfo(Y)) {
                return @as(Y, self.a);
            } else if (@typeInfo(U) == @typeInfo(Y)) {
                return @as(Y, self.b);
            } else {
                return null;
            }
        }

        pub fn first(self: Self) T {
            return self.a;
        }

        pub fn second(self: Self) U {
            return self.b;
        }
    };
}

pub fn Error(comptime T: type) type {
    @setRuntimeSafety(false);
    return struct {
        value: T,
        isError: bool,

        message: []const u8,

        const Self = @This();

        pub fn throw(message: []const u8) Self {
            @setRuntimeSafety(false);
            return Self{
                .value = undefined,
                .isError = true,
                .message = message,
            };
        }

        pub fn ok(value: T) Self {
            @setRuntimeSafety(false);
            return Self{
                .value = value,
                .isError = false,
                .message = "",
            };
        }

        pub fn unwrap(self: Self) T {
            @setRuntimeSafety(false);
            if (self.isError) {
                return undefined;
            } else {
                return self.value;
            }
        }

        pub fn isOk(self: Self) bool {
            @setRuntimeSafety(false);
            return !self.isError;
        }

        pub fn getError(self: Self) ?[]const u8 {
            @setRuntimeSafety(false);
            if (self.isError) {
                return self.message;
            } else {
                return null;
            }
        }
    };
}

pub fn Array(comptime T: type) type {
    return struct {
        ptr: ?[*]T,
        len: usize,
        capacity: usize,
        kernel: bool = false,

        const Self = @This();

        pub fn init() Self {
            return Self{
                .ptr = null,
                .len = 0,
                .capacity = 0,
            };
        }

        pub fn initKernel() Self {
            @setRuntimeSafety(false);
            return Self{
                .ptr = null,
                .len = 0,
                .capacity = 0,
                .kernel = true,
            };
        }

        pub fn fromData(data: []const T) Self {
            @setRuntimeSafety(false);
            const size = data.len;
            if (size == 0) {
                return Self.init();
            }

            const mem = alloc.request(size * @sizeOf(T)) orelse {
                sys.panic("Failed to allocate memory for array");
            };

            const ptr = @as([*]T, @alignCast(@ptrCast(mem)));
            for (0..size) |i| {
                ptr[i] = data[i];
            }

            return Self{
                .ptr = ptr,
                .len = size,
                .capacity = size,
            };
        }

        pub fn fromDataAtKernel(data: []const T) Self {
            @setRuntimeSafety(false);
            const size = data.len;
            if (size == 0) {
                return Self.init();
            }

            const mem = kalloc.requestKernel(size * @sizeOf(T)) orelse {
                sys.panic("Failed to allocate memory for array");
            };

            const ptr = @as([*]T, @alignCast(@ptrCast(mem)));
            for (0..size) |i| {
                ptr[i] = data[i];
            }

            return Self{
                .ptr = ptr,
                .len = size,
                .capacity = size,
            };
        }

        pub fn destroy(self: *Self) void {
            if (self.ptr) |ptr| {
                if (self.kernel) {
                    kalloc.freeKernel(@ptrCast(ptr));
                } else {
                    alloc.free(@ptrCast(ptr));
                }
            }

            self.ptr = null;
            self.len = 0;
            self.capacity = 0;
        }

        pub fn last(self: *Self) ?T {
            if (self.len == 0) {
                return null;
            }
            return self.ptr.?[self.len - 1];
        }

        pub fn pop(self: *Self) ?T {
            @setRuntimeSafety(false);
            if (self.len == 0) {
                return null;
            }
            self.len -= 1;
            const value = self.ptr.?[self.len];
            self.ptr.?[self.len] = undefined;
            return value;
        }

        pub fn append(self: *Self, value: T) void {
            @setRuntimeSafety(false);
            if (self.len >= self.capacity) {
                const err = self.grow();
                if (!err.isOk()) {
                    sys.panic(err.message);
                }
            }

            self.ptr.?[self.len] = value;
            self.len += 1;
        }

        fn grow(self: *Self) Error(void) {
            @setRuntimeSafety(false);
            const new_capacity: usize = if (self.capacity == 0) 4 else self.capacity * 2;
            const new_size = new_capacity * @sizeOf(T);
            var new_mem: ?[*]u8 = null;
            if (self.kernel) {
                new_mem = kalloc.requestKernel(new_size) orelse {
                    return Error(void).throw("Failed to allocate memory for array");
                };
            } else {
                new_mem = alloc.request(new_size) orelse {
                    return Error(void).throw("Failed to allocate memory for array");
                };
            }

            const new_ptr = @as([*]T, @alignCast(@ptrCast(new_mem.?)));

            if (self.ptr) |old_ptr| {
                for (0..self.len) |i| {
                    new_ptr[i] = old_ptr[i];
                }
                if (self.kernel) {
                    kalloc.freeKernel(@ptrCast(old_ptr));
                } else {
                    alloc.free(@ptrCast(old_ptr));
                }
            }

            self.ptr = new_ptr;
            self.capacity = new_capacity;
            return Error(void).ok({});
        }

        pub fn get(self: Self, index: usize) ?T {
            @setRuntimeSafety(false);
            if (index >= self.len) {
                return null;
            }
            return self.ptr.?[index];
        }

        pub fn set(self: *Self, index: usize, value: T) ?void {
            @setRuntimeSafety(false);
            if (index >= self.len) {
                return null;
            }
            self.ptr.?[index] = value;
            return null;
        }

        pub fn coerce(self: Self) []T {
            @setRuntimeSafety(false);
            return self.iterate();
        }

        pub fn getRest(self: Self, start: usize) ?Array(T) {
            @setRuntimeSafety(false);
            if (start >= self.len) {
                return null;
            }
            const data = self.ptr.?[start..self.len];
            const new_array = Array(T).fromData(data);
            return new_array;
        }

        pub fn getSlice(self: Self, start: usize, end: usize) ?[]T {
            @setRuntimeSafety(false);
            if (start >= self.len or end > self.len or start >= end) {
                return null;
            }
            return self.ptr.?[start..end];
        }

        pub fn joinIntoString(self: Self, delimiter: []const u8) str.String {
            @setRuntimeSafety(false);
            var result = str.DynamicString.init("");
            for (0..self.len) |i| {
                result.pushStr(self.ptr.?[i].coerce());
                result.pushStr(delimiter);
            }
            return result.coerce();
        }

        pub fn iterate(self: Self) []T {
            @setRuntimeSafety(false);
            if (self.ptr == null) return &[_]T{};
            return self.ptr.?[0..self.len];
        }

        pub fn remove(self: *Self, index: usize) ?T {
            @setRuntimeSafety(false);
            if (index >= self.len) {
                return null;
            }
            const value = self.ptr.?[index];
            for (index + 1..self.len) |i| {
                self.ptr.?[i - 1] = self.ptr.?[i];
            }
            self.len -= 1;
            self.ptr.?[self.len] = undefined; // Clear the last element
            return value;
        }

        pub fn removeWhere(self: *Self, predicate: fn (T) bool) ?T {
            @setRuntimeSafety(false);
            for (0..self.len) |i| {
                if (predicate(self.ptr.?[i])) {
                    return self.remove(i);
                }
            }
            return null; // No element found
        }
    };
}

pub fn Buffer(comptime T: type, comptime growSize: comptime_int) type {
    return struct {
        ptr: ?[*]T,
        len: usize,
        capacity: usize,

        const Self = @This();

        pub fn init() Self {
            return Self{
                .ptr = null,
                .len = 0,
                .capacity = 0,
            };
        }

        pub fn fromData(data: []const T) Self {
            @setRuntimeSafety(false);
            const size = data.len;
            if (size == 0) {
                return Self.init();
            }

            const mem = alloc.request(size * @sizeOf(T)) orelse {
                sys.panic("Failed to allocate memory for buffer");
            };

            const ptr = @as([*]T, @alignCast(@ptrCast(mem)));
            for (0..size) |i| {
                ptr[i] = data[i];
            }

            return Self{
                .ptr = ptr,
                .len = size,
                .capacity = size,
            };
        }

        pub fn destroy(self: *Self) void {
            if (self.ptr) |ptr| {
                alloc.free(@ptrCast(ptr));
            }
            self.ptr = null;
            self.len = 0;
            self.capacity = 0;
        }

        pub fn pop(self: *Self) ?T {
            @setRuntimeSafety(false);
            if (self.len == 0) return null;
            self.len -= 1;
            const value = self.ptr.?[self.len];
            self.ptr.?[self.len] = undefined;
            return value;
        }

        pub fn append(self: *Self, value: T) void {
            @setRuntimeSafety(false);
            if (self.len >= self.capacity) {
                const err = self.grow();
                if (!err.isOk()) {
                    sys.panic(err.message);
                }
            }
            self.ptr.?[self.len] = value;
            self.len += 1;
        }

        fn grow(self: *Self) Error(void) {
            @setRuntimeSafety(false);
            const new_capacity = self.capacity + growSize;
            const new_size = new_capacity * @sizeOf(T);
            const new_mem = alloc.request(new_size) orelse {
                return Error(void).throw("Failed to allocate memory");
            };

            const new_ptr = @as([*]T, @alignCast(@ptrCast(new_mem)));

            if (self.ptr) |old_ptr| {
                for (0..self.len) |i| {
                    new_ptr[i] = old_ptr[i];
                }
                alloc.free(@ptrCast(old_ptr));
            }

            self.ptr = new_ptr;
            self.capacity = new_capacity;
            return Error(void).ok({});
        }

        pub fn get(self: Self, index: usize) ?T {
            @setRuntimeSafety(false);
            if (index >= self.len) return null;
            return self.ptr.?[index];
        }

        pub fn set(self: *Self, index: usize, value: T) ?void {
            @setRuntimeSafety(false);
            if (index >= self.len) return null;
            self.ptr.?[index] = value;
            return null;
        }

        pub fn coerce(self: Self) []T {
            @setRuntimeSafety(false);
            return self.iterate();
        }

        pub fn iterate(self: Self) []T {
            @setRuntimeSafety(false);
            if (self.ptr == null) return &[_]T{};
            return self.ptr.?[0..self.len];
        }

        pub fn push(self: *Self, array: []const T) void {
            @setRuntimeSafety(false);
            const size = array.len;
            if (size == 0) return;

            if (self.len + size > self.capacity) {
                const err = self.grow();
                if (!err.isOk()) {
                    sys.panic(err.message);
                }
            }

            for (0..size) |i| {
                self.ptr.?[self.len + i] = array[i];
            }
            self.len += size;
        }
    };
}

pub fn Optional(comptime T: type) type {
    return struct {
        val: T = undefined,
        isSet: bool = false,

        const Self = @This();

        pub fn init() Self {
            return Self{
                .value = undefined,
                .isSet = false,
            };
        }

        pub fn none() Self {
            return Self{
                .val = undefined,
                .isSet = false,
            };
        }

        pub fn some(variable: T) Self {
            @setRuntimeSafety(false);
            return Self{
                .val = variable,
                .isSet = true,
            };
        }

        pub fn unwrap(self: Self) T {
            @setRuntimeSafety(false);
            if (!self.isSet) {
                return undefined;
            }
            return self.val;
        }

        pub fn isPresent(self: Self) bool {
            @setRuntimeSafety(false);
            return self.isSet;
        }
    };
}

pub fn Stream(comptime T: type) type {
    return struct {
        data: []const T,
        index: usize,

        const Self = @This();

        pub fn init(collection: []const T) Self {
            return Self{
                .data = collection,
                .index = 0,
            };
        }

        pub fn getPos(self: *Self) usize {
            @setRuntimeSafety(false);
            return self.index;
        }

        pub fn seek(self: *Self, index: usize) void {
            @setRuntimeSafety(false);
            if (index < self.data.len) {
                self.index = index; // Increment to point to the next element
            } else {
                sys.panic("Index out of bounds in PersistentList");
            }
        }

        pub fn getNext(self: *Self, n: usize) ?[]const T {
            @setRuntimeSafety(false);
            if (n == 0 or n + self.index > self.data.len) {
                return null;
            }

            return self.data[self.index .. self.index + n];
        }

        pub fn next(self: *Self) ?T {
            @setRuntimeSafety(false);
            if (self.index >= self.data.len) {
                return null;
            }
            const value = self.data[self.index];
            self.index += 1;
            return value;
        }

        pub fn get(self: *Self, n: usize) ?[]const T {
            @setRuntimeSafety(false);
            if (n == 0 or n + self.index > self.data.len) {
                return null;
            }

            const data = self.data[self.index .. self.index + n];
            self.index += n; // Adjust n to be the end index
            return data;
        }

        pub fn getUntil(self: *Self, terminator: T) ?[]const T {
            @setRuntimeSafety(false);
            const start_index = self.index;
            while (self.index < self.data.len) : (self.index += 1) {
                if (self.data[self.index] == terminator) {
                    return self.data[start_index..self.index];
                }
            }
            return null; // Terminator not found
        }

        pub fn skip(self: *Self, n: usize) void {
            @setRuntimeSafety(false);
            if (self.index + n > self.data.len) {
                sys.panic("Index out of bounds in Stream");
            }
            self.index += n;
        }

        pub fn goBack(self: *Self, n: usize) void {
            @setRuntimeSafety(false);
            if (self.index < n) {
                sys.panic("Cannot go back beyond the start of the stream");
            }
            self.index -= n;
        }

        pub fn getRemaining(self: *Self) []const T {
            @setRuntimeSafety(false);
            if (self.index >= self.data.len) {
                return &[_]T{};
            }
            return self.data[self.index..];
        }
    };
}

pub fn reinterpretBytes(comptime T: type, bytes: []const u8, littleEndian: bool) Optional(T) {
    @setRuntimeSafety(false);
    const size = @sizeOf(T);
    if (bytes.len != size) {
        return Optional(T).none();
    }

    var raw: [@sizeOf(T)]u8 = undefined;
    var i: usize = 0;
    while (i < size) : (i += 1) {
        if (littleEndian) {
            raw[i] = bytes[(size - 1) - i];
        } else {
            raw[i] = bytes[i];
        }
    }

    const result: T = @bitCast(raw);
    return Optional(T).some(result);
}

pub fn asLittleEndian(bytes: []const u8) []const u8 {
    @setRuntimeSafety(false);
    const size = bytes.len;
    var result: [*]u8 = @ptrCast(&bytes[0]);
    var i: usize = 0;
    while (i < size) : (i += 1) {
        result[i] = bytes[(size - 1) - i];
    }
    return result[0..size];
}

pub fn compareBytes(comptime T: type, a: []const T, b: []const T) bool {
    @setRuntimeSafety(false);
    if (a.len != b.len) {
        return false;
    }

    for (0..a.len) |i| {
        if (a[i] != b[i]) {
            return false;
        }
    }
    return true;
}

pub fn compareRange(comptime T: type, a: []const T, b: []const T, start: usize, end: usize) bool {
    @setRuntimeSafety(false);
    if (start >= a.len or end > a.len or end - start != b.len) {
        return false;
    }

    for (0..b.len) |i| {
        if (a[start + i] != b[i]) {
            return false;
        }
    }
    return true;
}

pub fn startsWith(comptime T: type, a: []const T, b: []const T) bool {
    @setRuntimeSafety(false);
    if (a.len < b.len) {
        return false;
    }

    for (0..b.len) |i| {
        if (a[i] != b[i]) {
            return false;
        }
    }
    return true;
}

pub fn concatBytes(comptime T: type, a: []const T, b: []const T) []T {
    @setRuntimeSafety(false);
    const result_len = a.len + b.len;
    var result: [*]T = alloc.request(result_len * @sizeOf(T)) orelse {
        sys.panic("Failed to allocate memory for concatenation");
    };
    for (0..a.len) |i| {
        result[i] = a[i];
    }
    for (0..b.len) |i| {
        result[a.len + i] = b[i];
    }
    return result[0..result_len];
}

pub fn readBytes(comptime size: comptime_int, buff: [*]u8) ?[]u8 {
    @setRuntimeSafety(false);
    const bytes = @as([*]u8, @ptrCast(buff))[0..size];
    if (bytes.len != size) {
        return null;
    }
    return bytes;
}

pub fn printStackTop() void {
    @setRuntimeSafety(false);
    const stack_tp = getStackTop();
    out.print("Stack top is: ");
    out.printHex(stack_tp);
    out.println("");
}

pub fn find(comptime T: type, data: []const T, value: T) ?usize {
    @setRuntimeSafety(false);
    for (0..data.len) |i| {
        if (data[i] == value) {
            return i;
        }
    }
    return null;
}

pub fn findLast(comptime T: type, data: []const T, value: T) ?usize {
    @setRuntimeSafety(false);
    if (data.len == 0) return null;

    var i: usize = data.len - 1;
    while (true) {
        if (data[i] == value) {
            return i;
        }
        if (i == 0) break;
        i -= 1;
    }
    return null;
}

pub fn printStack() void {
    @setRuntimeSafety(false);
    const stack_tp = getStackTop();
    out.print("Stack top is: ");
    out.printHex(stack_tp);
    out.println("");
    out.print("Stack bottom is: ");
    out.printn(@intFromPtr(@as(*u32, @ptrFromInt(stack_bottom))));
    out.println("");
    out.print("Stack size is:");
    out.printn(stack_tp - stack_bottom);
    out.println("");
}

pub fn isEmpty(comptime T: type, data: []const T) bool {
    @setRuntimeSafety(false);
    if (data.len == 0) {
        return true;
    }
    for (0..data.len) |i| {
        if (data[i] != 0x0) {
            return false;
        }
    }
    return true;
}

pub fn move(dst: [*]u8, src: [*]const u8, count: usize) void {
    @setRuntimeSafety(false);

    if (dst == src or count == 0) return;

    if (@intFromPtr(dst) < @intFromPtr(src) or @intFromPtr(dst) >= @intFromPtr(src) + count) {
        // No overlap or safe to copy forward
        var i: usize = 0;
        while (i < count) : (i += 1) {
            dst[i] = src[i];
        }
    } else {
        // Overlapping, copy backwards
        var i: usize = count;
        while (i > 0) : (i -= 1) {
            dst[i - 1] = src[i - 1];
        }
    }
}

pub fn reinterpretToBytes(comptime T: type, value: T) []const u8 {
    const ptr: *const [@sizeOf(T)]u8 = @ptrCast(&value);
    return &ptr.*;
}

pub fn WriteStream(comptime T: type) type {
    return struct {
        data: [*]T,
        len: usize,
        index: usize,

        const Self = @This();

        pub fn init(data: [*]T, n: usize) Self {
            return Self{
                .data = data,
                .len = n,
                .index = 0,
            };
        }

        pub fn write(self: *Self, len: usize, value: []const T) ?usize {
            @setRuntimeSafety(false);
            if (self.index + len > self.len) {
                return null;
            }

            for (0..len) |i| {
                self.data[self.index + i] = value[i];
            }
            self.index += len;
            return len;
        }

        pub fn seek(self: *Self, index: usize) void {
            @setRuntimeSafety(false);
            if (index < self.len) {
                self.index = index; // Increment to point to the next element
            } else {
                sys.panic("Index out of bounds in WriteStream");
            }
        }

        pub fn getPos(self: *Self) usize {
            @setRuntimeSafety(false);
            return self.index;
        }

        pub fn getNext(self: *Self, n: usize) ?[]const T {
            @setRuntimeSafety(false);
            if (n == 0 or n + self.index > self.len) {
                return null;
            }

            return self.data[self.index..n];
        }

        pub fn read(self: *Self, n: usize) ?[]const T {
            @setRuntimeSafety(false);
            if (n == 0 or n + self.index > self.len) {
                return null;
            }

            const data = self.data[self.index..n];
            self.index += n; // Adjust n to be the end index
            return data;
        }
    };
}

pub fn joinBytes(comptime T: type, a: []const T, b: []const T) []T {
    @setRuntimeSafety(false);
    const result_len = a.len + b.len;
    var result: [*]T = alloc.request(result_len * @sizeOf(T)) orelse {
        sys.panic("Failed to allocate memory for concatenation");
    };
    for (0..a.len) |i| {
        result[i] = a[i];
    }
    for (0..b.len) |i| {
        result[a.len + i] = b[i];
    }
    return result[0..result_len];
}

extern var stack_top: u8;
extern var stack_bottom: u8;

pub inline fn getStackTop() usize {
    @setRuntimeSafety(false);
    return @intFromPtr(&stack_top);
}

pub inline fn getStackBottom() usize {
    @setRuntimeSafety(false);
    return @intFromPtr(&stack_bottom);
}
pub fn append(comptime T: type, array: []T, elem: T) []T {
    @setRuntimeSafety(false);
    const new_len = array.len + 1;
    const result = kalloc.requestKernel(new_len * @sizeOf(T)) orelse {
        sys.panic("Failed to allocate memory for append");
    };

    const new_array = @as([*]T, @alignCast(@ptrCast(result)));

    for (0..array.len) |i| {
        new_array[i] = array[i];
    }

    new_array[array.len] = elem;

    return new_array[0..new_len];
}

pub fn findPtr(comptime T: type, ptr: [*]const T, elem: T) usize {
    @setRuntimeSafety(false);
    var i: usize = 0;
    while (true) : (i += 1) {
        if (ptr[i] == elem) {
            return i;
        }
    }
    return ptr.len;
}

pub fn copySafe(src: []const u8, dst: [*]u8, len: usize) void {
    for (0..len) |i| {
        dst[i] = src[i];
    }

    if (len > src.len) {
        for (src.len..len) |i| {
            dst[i] = 0;
        }
    }
}

pub fn split(str_data: []const u8, delimiter: u8) Array([]const u8) {
    @setRuntimeSafety(false);
    var result = Array([]const u8).init();

    if (str_data.len == 0) {
        return result;
    }

    var start: usize = 0;

    for (0..str_data.len) |i| {
        if (str_data[i] == delimiter) {
            if (i > start) {
                result.append(str_data[start..i]);
            }
            start = i + 1;
        }
    }

    if (start < str_data.len) {
        result.append(str_data[start..]);
    }

    return result;
}

pub fn contains(comptime T: type, array: []const T, elem: T) bool {
    @setRuntimeSafety(false);
    for (0..array.len) |i| {
        if (T == []const u8) {
            if (compareBytes(u8, array[i], elem)) {
                return true;
            }
        } else {
            if (array[i] == elem) {
                return true;
            }
        }
    }
    return false;
}
