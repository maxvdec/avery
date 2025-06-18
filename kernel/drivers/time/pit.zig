const sys = @import("system");
const out = @import("output");
const irq = @import("irq");

pub var timerTicks: u32 = 0;
pub var seconds: u32 = 0;
pub var milliseconds: u32 = 0;
pub var initialized: bool = false;

var scheduler_callback: ?*const fn () void = null;
var last_scheduler_call: u32 = 0;
const SCHEDULER_INTERVAL: u32 = 10;

fn calculateTimerPhase(hz: u32) void {
    const divisor: u32 = 1193180 / hz;
    const low: u8 = @intCast(divisor & 0xFF);
    const high: u8 = @intCast((divisor >> 8) & 0xFF);

    sys.outb(0x43, 0x36);
    sys.outb(0x40, low);
    sys.outb(0x40, high);
}

const MS_PER_TICK = 55;

fn timeHandler(_: *sys.regs) void {
    timerTicks += 1;
    milliseconds += MS_PER_TICK;

    if (milliseconds >= 1000) {
        seconds += 1;
        milliseconds -= 1000;
    }

    if (scheduler_callback != null) {
        const current_time = milliseconds + seconds * 1000;
        if (current_time - last_scheduler_call >= SCHEDULER_INTERVAL) {
            last_scheduler_call = current_time;
            scheduler_callback.?();
        }
    }
}

pub fn setSchedulerCallback(callback: *const fn () void) void {
    @setRuntimeSafety(false);
    scheduler_callback = callback;
    last_scheduler_call = milliseconds + seconds * 1000;
}

pub fn init() void {
    @setRuntimeSafety(false);
    irq.installHandler(0, &timeHandler);
    initialized = true;
}
