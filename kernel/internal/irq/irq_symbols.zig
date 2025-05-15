const sys = @import("system");

const irqElement = ?*const fn (*sys.regs) void;

pub export var irqRoutines: [16]irqElement = [_]irqElement{
    null, null, null, null,
    null, null, null, null,
    null, null, null, null,
    null, null, null, null,
};

export fn irq_handler(r: *sys.regs) void {
    @setRuntimeSafety(false);
    const irq = r.int_no - 32;
    if (irqRoutines[irq] != null) {
        irqRoutines[irq].?(r);
    }

    if (r.int_no >= 40) {
        sys.outb(0xA0, 0x20);
    }
    sys.outb(0x20, 0x20);
}
