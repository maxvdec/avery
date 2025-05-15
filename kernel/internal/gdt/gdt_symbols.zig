const GdtEntry = packed struct {
    limit_low: u16 = 0,
    base_low: u16 = 0,
    base_middle: u8 = 0,
    access: u8 = 0,
    granularity: u8 = 0,
    base_high: u8 = 0,
};

const GdtPointer = extern struct {
    limit: u16 = 0,
    base: u32 = 0,
};

export var gdt: [3]GdtEntry = [_]GdtEntry{ .{}, .{}, .{} };
export var gp: GdtPointer align(16) = .{};
