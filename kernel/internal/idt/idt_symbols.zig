const idtEntry = packed struct { base_lo: u16 = 0, sel: u16 = 0, always0: u8 = 0, flags: u8 = 0, base_hi: u16 = 0 };

const idtPtr = packed struct {
    limit: u16 = 0,
    base: u32 = 0,
};

export var idt: [256]idtEntry = undefined;
var idt_ptr: idtPtr = .{};

export fn get_idt_ptr() *idtPtr {
    return &idt_ptr;
}
