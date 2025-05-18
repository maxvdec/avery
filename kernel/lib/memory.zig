const alloc = @import("allocator");

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
    return struct {
        value: T,
        isError: bool,

        message: []const u8,

        const Self = @This();

        pub fn throw(message: []const u8) Self {
            return Self{
                .value = undefined,
                .isError = true,
                .message = message,
            };
        }

        pub fn ok(value: T) Self {
            return Self{
                .value = value,
                .isError = false,
                .message = "",
            };
        }

        pub fn unwrap(self: Self) T {
            if (self.isError) {
                return undefined;
            } else {
                return self.value;
            }
        }

        pub fn isOk(self: Self) bool {
            return !self.isError;
        }

        pub fn getError(self: Self) ?[]const u8 {
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

        const Self = @This();

        pub fn init() Self {
            return Self{
                .ptr = null,
                .len = 0,
                .capacity = 0,
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

        pub fn append(self: *Self, value: T) void {
            @setRuntimeSafety(false);
            if (self.len >= self.capacity) {
                _ = self.grow();
            }

            self.ptr.?[self.len] = value;
            self.len += 1;
        }

        fn grow(self: *Self) Error(void) {
            @setRuntimeSafety(false);
            const new_capacity: usize = if (self.capacity == 0) 4 else self.capacity * 2;
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

        pub fn iterate(self: Self) []T {
            @setRuntimeSafety(false);
            if (self.ptr == null) return &[_]T{};
            return @as([*]T, @ptrCast(self.ptr.?))[0..self.len];
        }
    };
}
