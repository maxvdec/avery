const sys = @import("system");
const idt = @import("idt");

extern fn irq0() void;
extern fn irq1() void;
extern fn irq2() void;
extern fn irq3() void;
extern fn irq4() void;
extern fn irq5() void;
extern fn irq6() void;
extern fn irq7() void;
extern fn irq8() void;
extern fn irq9() void;
extern fn irq10() void;
extern fn irq11() void;
extern fn irq12() void;
extern fn irq13() void;
extern fn irq14() void;
extern fn irq15() void;

const irqElement = ?*const fn (*sys.regs) void;

extern var irqRoutines: [16]irqElement;

pub fn installHandler(irq: u8, handler: *const fn (*sys.regs) void) void {
    @setRuntimeSafety(false);
    irqRoutines[irq] = handler;
}

pub fn removeHandler(irq: u8) void {
    @setRuntimeSafety(false);
    irqRoutines[irq] = null;
}

pub fn remap() void {
    @setRuntimeSafety(false);
    sys.outb(0x20, 0x11);
    sys.outb(0xA0, 0x11);
    sys.outb(0x21, 0x20);
    sys.outb(0xA1, 0x28);
    sys.outb(0x21, 0x04);
    sys.outb(0xA1, 0x02);
    sys.outb(0x21, 0x01);
    sys.outb(0xA1, 0x01);
    sys.outb(0x21, 0x0);
    sys.outb(0xA1, 0x0);
}

pub fn init() void {
    @setRuntimeSafety(false);
    remap();

    idt.setGate(32, @as(u64, @intFromPtr(&irq0)), 0x08, 0x8E);
    idt.setGate(33, @as(u64, @intFromPtr(&irq1)), 0x08, 0x8E);
    idt.setGate(34, @as(u64, @intFromPtr(&irq2)), 0x08, 0x8E);
    idt.setGate(35, @as(u64, @intFromPtr(&irq3)), 0x08, 0x8E);
    idt.setGate(36, @as(u64, @intFromPtr(&irq4)), 0x08, 0x8E);
    idt.setGate(37, @as(u64, @intFromPtr(&irq5)), 0x08, 0x8E);
    idt.setGate(38, @as(u64, @intFromPtr(&irq6)), 0x08, 0x8E);
    idt.setGate(39, @as(u64, @intFromPtr(&irq7)), 0x08, 0x8E);
    idt.setGate(40, @as(u64, @intFromPtr(&irq8)), 0x08, 0x8E);
    idt.setGate(41, @as(u64, @intFromPtr(&irq9)), 0x08, 0x8E);
    idt.setGate(42, @as(u64, @intFromPtr(&irq10)), 0x08, 0x8E);
    idt.setGate(43, @as(u64, @intFromPtr(&irq11)), 0x08, 0x8E);
    idt.setGate(44, @as(u64, @intFromPtr(&irq12)), 0x08, 0x8E);
    idt.setGate(45, @as(u64, @intFromPtr(&irq13)), 0x08, 0x8E);
    idt.setGate(46, @as(u64, @intFromPtr(&irq14)), 0x08, 0x8E);
    idt.setGate(47, @as(u64, @intFromPtr(&irq15)), 0x08, 0x8E);
}
