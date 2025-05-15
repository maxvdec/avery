const GdtEntry = packed struct {
    limit_low: u16,
    base_low: u16,
    base_middle: u8,
    access: u8,
    granularity: u8,
    base_high: u8,
};

const GdtPointer = packed struct {
    limit: u16,
    base: u32,
};

extern var gdt: [3]GdtEntry;
extern fn get_gdt_ptr() *GdtPointer;

extern fn gdt_flush() void;

fn setGate(num: u32, base: u64, limit: u64, access: u8, gran: u8) void {
    @setRuntimeSafety(false);
    gdt[num].base_low = @as(u16, @intCast(base & 0xFFFF));
    gdt[num].base_middle = @as(u8, @intCast((base >> 16) & 0xFF));
    gdt[num].base_high = @as(u8, @intCast((base >> 24) & 0xFF));
    gdt[num].limit_low = @as(u16, @intCast(limit & 0xFFFF));
    gdt[num].granularity = @as(u8, @intCast(((limit >> 16) & 0x0F) | (gran & 0xF0)));
    gdt[num].access = access;
}

pub fn init() void {
    @setRuntimeSafety(false);
    const gp = get_gdt_ptr();
    gp.limit = (@sizeOf(GdtEntry) * 3) - 1;
    gp.base = @as(u32, @intCast(@intFromPtr(&gdt)));

    setGate(0, 0, 0, 0, 0);
    setGate(1, 0, 0xFFFFFFFF, 0x9A, 0xCF);
    setGate(2, 0, 0xFFFFFFFF, 0x92, 0xCF);

    gdt_flush();
}
