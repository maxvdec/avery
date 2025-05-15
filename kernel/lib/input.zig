const str = @import("string");
const keyboard = @import("keyboard");

pub fn readln() str.String {
    var buffer: [1024]u8 = undefined;
    var i: usize = 0;
    keyboard.enableKeyboard();

    while (true) {
        const chr = keyboard.currentChar;
        if (chr == 0) {
            continue;
        } else {
            if (chr == '\n' or chr == '\r') {
                break;
            }
            buffer[i] = chr;
            i += 1;
            keyboard.currentChar = 0;
        }
    }
    keyboard.disableKeyboard();

    return str.String.fromRuntime(&buffer[0..i]);
}
