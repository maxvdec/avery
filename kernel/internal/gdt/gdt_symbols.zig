const GdtEntry = packed struct {
    limit_low: u16 = 0,
    base_low: u16 = 0,
    base_middle: u8 = 0,
    access: u8 = 0,
    granularity: u8 = 0,
    base_high: u8 = 0,
};

const GdtPointer = packed struct {
    limit: u16 = 0,
    base: u32 = 0,
};

export var gdt: [6]GdtEntry = [_]GdtEntry{ .{}, .{}, .{}, .{}, .{}, .{} };
var gp: GdtPointer align(16) = .{};

export fn get_gdt_ptr() *GdtPointer {
    return &gp;
}
