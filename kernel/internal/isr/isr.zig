const str = @import("string");
const idt = @import("idt");
const out = @import("output");

extern fn isr0() void;
extern fn isr1() void;
extern fn isr2() void;
extern fn isr3() void;
extern fn isr4() void;
extern fn isr5() void;
extern fn isr6() void;
extern fn isr7() void;
extern fn isr8() void;
extern fn isr9() void;
extern fn isr10() void;
extern fn isr11() void;
extern fn isr12() void;
extern fn isr13() void;
extern fn isr14() void;
extern fn isr15() void;
extern fn isr16() void;
extern fn isr17() void;
extern fn isr18() void;
extern fn isr19() void;
extern fn isr20() void;
extern fn isr21() void;
extern fn isr22() void;
extern fn isr23() void;
extern fn isr24() void;
extern fn isr25() void;
extern fn isr26() void;
extern fn isr27() void;
extern fn isr28() void;
extern fn isr29() void;
extern fn isr30() void;
extern fn isr31() void;

pub const EXCEPTION_MESSAGES = [_]str.String{
    str.make("Division by zero"),
    str.make("Debug exception"),
    str.make("Non-maskable interrupt"),
    str.make("Breakpoint exception"),
    str.make("Overflow exception"),
    str.make("Out of bounds exception"),
    str.make("Invalid opcode exception"),
    str.make("No coprocessor exception"),
    str.make("Double fault exception"),
    str.make("Coprocessor segment overrun"),
    str.make("Bad TSS exception"),
    str.make("Segment not present exception"),
    str.make("Stack fault exception"),
    str.make("General protection fault"),
    str.make("Page fault exception"),
    str.make("Unknown interrupt exception"),
    str.make("Coprocessor fault exception"),
    str.make("Alignment check exception"),
    str.make("Machine check exception"),
    str.make("Reserved"),
    str.make("Reserved"),
    str.make("Reserved"),
    str.make("Reserved"),
    str.make("Reserved"),
    str.make("Reserved"),
    str.make("Reserved"),
    str.make("Reserved"),
    str.make("Reserved"),
    str.make("Reserved"),
    str.make("Reserved"),
    str.make("Reserved"),
};

pub fn init() void {
    @setRuntimeSafety(false);
    idt.setGate(0, @as(u64, @intFromPtr(&isr0)), 0x08, 0x8E);
    idt.setGate(1, @as(u64, @intFromPtr(&isr1)), 0x08, 0x8E);
    idt.setGate(2, @as(u64, @intFromPtr(&isr2)), 0x08, 0x8E);
    idt.setGate(3, @as(u64, @intFromPtr(&isr3)), 0x08, 0x8E);
    idt.setGate(4, @as(u64, @intFromPtr(&isr4)), 0x08, 0x8E);
    idt.setGate(5, @as(u64, @intFromPtr(&isr5)), 0x08, 0x8E);
    idt.setGate(6, @as(u64, @intFromPtr(&isr6)), 0x08, 0x8E);
    idt.setGate(7, @as(u64, @intFromPtr(&isr7)), 0x08, 0x8E);
    idt.setGate(8, @as(u64, @intFromPtr(&isr8)), 0x08, 0x8E);
    idt.setGate(9, @as(u64, @intFromPtr(&isr9)), 0x08, 0x8E);
    idt.setGate(10, @as(u64, @intFromPtr(&isr10)), 0x08, 0x8E);
    idt.setGate(11, @as(u64, @intFromPtr(&isr11)), 0x08, 0x8E);
    idt.setGate(12, @as(u64, @intFromPtr(&isr12)), 0x08, 0x8E);
    idt.setGate(13, @as(u64, @intFromPtr(&isr13)), 0x08, 0x8E);
    idt.setGate(14, @as(u64, @intFromPtr(&isr14)), 0x08, 0x8E);
    idt.setGate(15, @as(u64, @intFromPtr(&isr15)), 0x08, 0x8E);
    idt.setGate(16, @as(u64, @intFromPtr(&isr16)), 0x08, 0x8E);
    idt.setGate(17, @as(u64, @intFromPtr(&isr17)), 0x08, 0x8E);
    idt.setGate(18, @as(u64, @intFromPtr(&isr18)), 0x08, 0x8E);
    idt.setGate(19, @as(u64, @intFromPtr(&isr19)), 0x08, 0x8E);
    idt.setGate(20, @as(u64, @intFromPtr(&isr20)), 0x08, 0x8E);
    idt.setGate(21, @as(u64, @intFromPtr(&isr21)), 0x08, 0x8E);
    idt.setGate(22, @as(u64, @intFromPtr(&isr22)), 0x08, 0x8E);
    idt.setGate(23, @as(u64, @intFromPtr(&isr23)), 0x08, 0x8E);
    idt.setGate(24, @as(u64, @intFromPtr(&isr24)), 0x08, 0x8E);
    idt.setGate(25, @as(u64, @intFromPtr(&isr25)), 0x08, 0x8E);
    idt.setGate(26, @as(u64, @intFromPtr(&isr26)), 0x08, 0x8E);
    idt.setGate(27, @as(u64, @intFromPtr(&isr27)), 0x08, 0x8E);
    idt.setGate(28, @as(u64, @intFromPtr(&isr28)), 0x08, 0x8E);
    idt.setGate(29, @as(u64, @intFromPtr(&isr29)), 0x08, 0x8E);
    idt.setGate(30, @as(u64, @intFromPtr(&isr30)), 0x08, 0x8E);
    idt.setGate(31, @as(u64, @intFromPtr(&isr31)), 0x08, 0x8E);
}
