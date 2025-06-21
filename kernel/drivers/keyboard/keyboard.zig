const sys = @import("system");
const irq = @import("irq");
const kbdEs = @import("keyboard_es");
const out = @import("output");
const scheduler = @import("scheduler");

pub var shift: bool = false;
pub var currentChar: u8 = 0;
var keyboard_init = false;

const INPUT_BUFFER_SIZE = 256;
var input_buffer: [INPUT_BUFFER_SIZE]u8 = undefined;
var buffer_head: usize = 0;
var buffer_tail: usize = 0;
var buffer_count: usize = 0;

var in_keyboard_handler: bool = false;

fn keyboard_handler(_: *sys.regs) void {
    @setRuntimeSafety(false);

    if (in_keyboard_handler) return;
    in_keyboard_handler = true;
    defer in_keyboard_handler = false;
    const scancode: u8 = sys.inb(0x60);
    out.preserveMode();
    out.switchToSerial();
    out.printHex(scancode);
    out.restoreMode();
    if (scancode & 0x80 != 0) {
        currentChar = 0;
        if (scancode == 0xAA) {
            shift = false;
        }
    } else {
        if (scancode == 0x2A) {
            shift = true;
        } else {
            if (shift) {
                const key: u8 = kbdEs.kbES_SHIFT[scancode];
                if (key != 0) {
                    currentChar = key;
                }
            } else {
                const key: u8 = kbdEs.kbES[scancode];
                currentChar = key;
            }

            if (currentChar != 0) {
                pushChar(currentChar);

                wakeupInputWaiters();
            }
        }
    }
}

fn wakeupInputWaiters() void {
    @setRuntimeSafety(false);

    if (scheduler.scheduler == null) return;

    var i: usize = 0;
    while (i < scheduler.scheduler.?.blocked_queue.len) : (i += 1) {
        const blocked_proc = scheduler.scheduler.?.blocked_queue.get(i);
        if (blocked_proc) |proc| {
            if (proc.input_state != null and proc.input_state.?.reading) {
                out.preserveMode();
                out.switchToSerial();
                out.print("Awakening process ");
                out.printn(proc.pid);
                out.println("");
                out.restoreMode();
                scheduler.scheduler.?.unblockProcess(proc);
                break;
            }
        }
    }
}

pub fn getChar() ?u8 {
    return popChar();
}

pub fn hasInput() bool {
    return hasChars();
}

fn pushChar(ch: u8) void {
    if (buffer_count < INPUT_BUFFER_SIZE) {
        input_buffer[buffer_head] = ch;
        buffer_head = (buffer_head + 1) % INPUT_BUFFER_SIZE;
        buffer_count += 1;
    }
}

fn popChar() ?u8 {
    if (buffer_count == 0) {
        return null;
    }

    const ch = input_buffer[buffer_tail];
    buffer_tail = (buffer_tail + 1) % INPUT_BUFFER_SIZE;
    buffer_count -= 1;
    return ch;
}

fn hasChars() bool {
    return buffer_count > 0;
}

pub fn enableKeyboard() void {
    @setRuntimeSafety(false);
    if (keyboard_init) {
        return;
    }
    irq.installHandler(1, &keyboard_handler);
    keyboard_init = true;
}

pub fn isEnabled() bool {
    @setRuntimeSafety(false);
    return irq.isIrqHandlerInstalled(1);
}

pub fn disableKeyboard() void {
    @setRuntimeSafety(false);
    if (!keyboard_init) {
        return;
    }
    keyboard_init = false;
    irq.removeHandler(1);
}
