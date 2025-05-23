const vgaTxt = @import("text_vga");
const str = @import("string");
const output = @import("system");
const serial = @import("serial");

pub const VgaTextColor = vgaTxt.VgaTextColor;

pub const OutputMode = enum {
    VgaText,
    Serial,
};

pub var mode: OutputMode = OutputMode.VgaText;

pub fn clear() void {
    vgaTxt.clear();
}

pub fn switchToSerial() void {
    mode = OutputMode.Serial;
}

pub fn initOutputs() void {
    vgaTxt.initVgaText();
    serial.initSerial();
}

pub fn char(chr: str.char) void {
    if (mode == OutputMode.Serial) {
        serial.writeChar(chr);
    } else {
        vgaTxt.putChar(chr);
    }
}

pub fn print(string: []const u8) void {
    const stdStr = str.makeRuntime(string);
    if (mode == OutputMode.Serial) {
        serial.writeString(stdStr);
    } else {
        vgaTxt.printStr(stdStr);
    }
}

pub fn printchar(chr: str.char) void {
    if (mode == OutputMode.Serial) {
        serial.writeChar(chr);
    } else {
        vgaTxt.putChar(chr);
    }
}

pub fn println(string: []const u8) void {
    const stdStr = str.makeRuntime(string);
    if (mode == OutputMode.Serial) {
        serial.writeString(stdStr);
        serial.writeString(str.make("\n"));
    } else {
        vgaTxt.printStr(stdStr);
        vgaTxt.printStr(str.make("\n"));
    }
}

pub fn setCursorPos(x: u8, y: u8) void {
    vgaTxt.setCursorPos(x, y);
}

pub fn printU64(num: u64) void {
    @setRuntimeSafety(false);
    var buffer: [20]u8 = undefined;
    var i: usize = buffer.len;
    var v = num;

    if (v == 0) {
        if (mode == OutputMode.Serial) {
            serial.writeChar('0');
        } else {
            vgaTxt.putChar('0');
        }
        return;
    }

    while (v != 0) : (i -= 1) {
        const digit = @as(u8, @intCast(v % 10));
        buffer[i - 1] = '0' + digit;
        v /= 10;
    }

    const length = buffer.len - i;

    for (0..length) |j| {
        if (mode == OutputMode.Serial) {
            serial.writeChar(buffer[i + j]);
        } else {
            vgaTxt.putChar(buffer[i + j]);
        }
    }
}

pub fn printn(num: u32) void {
    @setRuntimeSafety(false);
    var buffer: [20]u8 = undefined;
    var i: usize = buffer.len;
    var v = num;

    if (v == 0) {
        if (mode == OutputMode.Serial) {
            serial.writeChar('0');
        } else {
            vgaTxt.putChar('0');
        }
        return;
    }

    while (v != 0) : (i -= 1) {
        const digit = @as(u8, @intCast(v % 10));
        buffer[i - 1] = '0' + digit;
        v /= 10;
    }

    const length = buffer.len - i;

    for (0..length) |j| {
        if (mode == OutputMode.Serial) {
            serial.writeChar(buffer[i + j]);
        } else {
            vgaTxt.putChar(buffer[i + j]);
        }
    }
}

pub fn printHex(num: u64) void {
    @setRuntimeSafety(false);
    print("0x");
    var buffer: [16]u8 = undefined;
    var i: usize = buffer.len;
    var v = num;

    if (v == 0) {
        if (mode == OutputMode.Serial) {
            serial.writeChar('0');
        } else {
            vgaTxt.putChar('0');
        }
        return;
    }

    while (v != 0) : (i -= 1) {
        const digit = @as(u8, @intCast(v % 16));
        buffer[i - 1] = if (digit < 10) '0' + digit else 'A' + digit - 10;
        v /= 16;
    }

    const length = buffer.len - i;

    for (0..length) |j| {
        if (mode == OutputMode.Serial) {
            serial.writeChar(buffer[i + j]);
        } else {
            vgaTxt.putChar(buffer[i + j]);
        }
    }
}

pub fn printstr(string: str.String) void {
    if (mode == OutputMode.Serial) {
        serial.writeString(string);
    } else {
        vgaTxt.printStr(string);
    }
}

pub fn setTextColor(fg: VgaTextColor, bg: VgaTextColor) void {
    vgaTxt.setTextColor(fg, bg);
}
