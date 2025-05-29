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

    while (true) {
        out.term.updateCursor();

        const chr = keyboard.currentChar;
        if (chr == 0) {
            continue;
        }

        keyboard.currentChar = 0;

        if (chr == 0x08) {
            if (i > 0) {
                i -= 1;
                buffer[i] = 0;
                out.printchar(chr);
            }
        } else if (chr == '\n' or chr == '\r') {
            out.printchar(chr);
            break;
        } else {
            if (i < buffer.len - 1) {
                buffer[i] = chr;
                i += 1;
                out.printchar(chr);
            }
        }
    }
    return buffer[0..i];
}
