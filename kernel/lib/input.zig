const str = @import("string");
const keyboard = @import("keyboard");
const out = @import("output");
const mem = @import("memory");
const sys = @import("system");

pub const InputState = struct {
    buffer: ?[*]u8,
    position: usize,
    max_len: usize,
    reading: bool,

    pub fn new() InputState {
        return InputState{
            .buffer = null,
            .position = 0,
            .max_len = 0,
            .reading = false,
        };
    }

    pub fn reset(self: *InputState) void {
        self.position = 0;
        self.buffer = null;
        self.max_len = 0;
        self.reading = false;
    }
};

pub fn readln() []const u8 {
    @setRuntimeSafety(false);
    var buffer: [1024]u8 = undefined;
    var i: usize = 0;
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

pub fn readbytes(len: usize) []const u8 {
    @setRuntimeSafety(false);
    var buffer: [1024]u8 = [_]u8{0} ** 1024;
    if (len > buffer.len) {
        return &[_]u8{}; // Return empty slice if requested length exceeds buffer size
    }

    var i: usize = 0;
    keyboard.currentChar = 0;

    while (i < len) {
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
            while (i < len) {
                buffer[i] = 0;
                i += 1;
            }
            break;
        } else {
            if (i < buffer.len - 1) {
                buffer[i] = chr;
                i += 1;
                out.printchar(chr);
            }
        }
    }
    return buffer[0..len];
}

pub fn readToPtr(ptr: [*]u8, maxLen: usize) void {
    @setRuntimeSafety(false);
    var i: usize = mem.findPtr(u8, ptr, 0);
    keyboard.currentChar = 0;

    while (i < maxLen) {
        out.term.updateCursor();

        const chr = keyboard.currentChar;
        if (chr == 0) {
            continue;
        }

        keyboard.currentChar = 0;

        if (chr == 0x08) {
            if (i > 0) {
                i -= 1;
                ptr[i] = 0;
                out.printchar(chr);
            }
        } else if (chr == '\n' or chr == '\r') {
            out.printchar(chr);
            while (i < maxLen) {
                ptr[i] = 0xFF;
                i += 1;
            }
            break;
        } else {
            if (i < maxLen - 1) {
                ptr[i] = chr;
                i += 1;
                out.printchar(chr);
            }
        }
    }
}
