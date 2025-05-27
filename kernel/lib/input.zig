const str = @import("string");
const keyboard = @import("keyboard");
const out = @import("output");
const mem = @import("memory");
const sys = @import("system");

pub fn readln() []const u8 {
    @setRuntimeSafety(false);
    var buffer: [1024]u8 = undefined;
    var i: usize = 0;
    keyboard.enableKeyboard();
    keyboard.currentChar = 0;
    keyboard.shift = false;

    var backspaceCombo: u32 = 0;

    sys.delay(50);

    while (true) {
        //out.term.updateCursor();

        const chr = keyboard.currentChar;
        if (chr == 0) {
            continue;
        } else {
            if (chr == 0x08) {
                backspaceCombo += 1;
                if (i > 0) {
                    buffer[i] = 0;
                    i -= 1;
                }
            }

            if (backspaceCombo > i - 1) {
                backspaceCombo = 0;
                continue;
            }
            out.printchar(chr);

            if (chr == 0x08) {
                continue;
            }

            if (chr == '\n' or chr == '\r') {
                keyboard.currentChar = 0;
                break;
            }
            if (i < buffer.len - 1) {
                buffer[i] = chr;
                i += 1;
            }
            keyboard.currentChar = 0;
        }
    }
    return buffer[0..i];
}
