const str = @import("string");
const keyboard = @import("keyboard");
const out = @import("output");

pub fn readln() str.String {
    @setRuntimeSafety(false);
    var buffer: [1024]u8 = undefined;
    var i: usize = 0;
    keyboard.enableKeyboard();

    while (true) {
        const chr = keyboard.currentChar;
        if (chr == 0) {
            continue;
        } else {
            out.printchar(chr);
            if (chr == '\n' or chr == '\r') {
                break;
            }
            buffer[i] = chr;
            i += 1;
            keyboard.currentChar = 0;
        }
    }
    keyboard.disableKeyboard();

    return str.String.fromRuntime(buffer[0..i]);
}
