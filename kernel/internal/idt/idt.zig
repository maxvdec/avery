const sys = @import("system");
const mem = @import("memory");

const idtEntry = extern struct { base_lo: u16 = 0, sel: u16 = 0, always0: u8 = 0, flags: u8 = 0, base_hi: u16 = 0 };

const idtPtr = packed struct {
    limit: u16 = 0,
    base: u32 = 0,
};

extern var idt: [256]idtEntry;
extern fn get_idt_ptr() *idtPtr;

extern fn idt_load() void;

pub fn init() void {
    var idt_ptr: *idtPtr = get_idt_ptr();
    idt_ptr.limit = (@sizeOf(idtEntry) * 256) - 1;
    idt_ptr.base = @as(u32, @intCast(@intFromPtr(&idt)));

    _ = sys.memset(@as([*]u8, @ptrCast(&idt)), 0, @sizeOf(idtEntry) * 256);

    idt_load();
}

pub fn setGate(num: u8, base: u64, sel: u16, flags: u8) void {
    @setRuntimeSafety(false);
    idt[num].base_lo = @as(u16, @intCast(base & 0xFFFF));
    idt[num].base_hi = @as(u16, @intCast((base >> 16) & 0xFFFF));
    idt[num].sel = sel;
    idt[num].always0 = 0;
    idt[num].flags = flags;
}
