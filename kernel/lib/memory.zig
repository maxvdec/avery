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
