const sys = @import("system");
const irq = @import("irq");
const kbdEs = @import("keyboard_es");
const out = @import("output");

pub var shift: bool = false;
pub var currentChar: u8 = 0;

fn keyboard_handler(_: *sys.regs) void {
    @setRuntimeSafety(false);
    const scancode: u8 = sys.inb(0x60);
    if (scancode & 0x80 != 0) {
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
                if (key != 0) {
                    currentChar = key;
                }
            }
        }
    }
}

pub fn enableKeyboard() void {
    @setRuntimeSafety(false);
    irq.installHandler(1, &keyboard_handler);
}

pub fn disableKeyboard() void {
    @setRuntimeSafety(false);
    irq.removeHandler(1);
}
