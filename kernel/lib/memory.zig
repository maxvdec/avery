pub fn Pointer(comptime T: type) type {
    return struct {
        data: [*]T,

        const Self = @This();

        pub fn init(data: [*]T) Self {
            return Self{ .data = data };
        }

        pub fn get(self: Self, index: usize) *T {
            return &self.data[index];
        }

        pub fn getValue(self: Self, index: usize) T {
            return self.data[index];
        }

        pub fn set(self: Self, index: usize, value: T) void {
            self.data[index] = value;
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
