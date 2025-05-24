const vgaTxt = @import("text_vga");
const str = @import("string");
const output = @import("system");
const serial = @import("serial");
const terminal = @import("terminal");

pub const VgaTextColor = vgaTxt.VgaTextColor;

pub const OutputMode = enum {
    VgaText,
    Serial,
    Graphics,
};

pub var mode: OutputMode = OutputMode.VgaText;
var modeSave: OutputMode = OutputMode.VgaText;

pub var term: *terminal.FramebufferTerminal = undefined;

pub fn clear() void {
    if (mode == OutputMode.VgaText) {
        vgaTxt.clear();
    } else if (mode == OutputMode.Graphics) {
        term.clear();
    }
}

pub fn preserveMode() void {
    modeSave = mode;
}

pub fn restoreMode() void {
    mode = modeSave;
}

pub fn switchToSerial() void {
    mode = OutputMode.Serial;
}

pub fn switchToVga() void {
    mode = OutputMode.VgaText;
}

pub fn switchToGraphics(fbTerminal: *terminal.FramebufferTerminal) void {
    mode = OutputMode.Graphics;
    term = fbTerminal;
}

pub fn initOutputs() void {
    vgaTxt.initVgaText();
    serial.initSerial();
}

pub fn char(chr: str.char) void {
    if (mode == OutputMode.Serial) {
        serial.writeChar(chr);
    } else if (mode == OutputMode.VgaText) {
        vgaTxt.putChar(chr);
    } else if (mode == OutputMode.Graphics) {
        term.putChar(chr);
        term.refresh();
    }
}

pub fn print(string: []const u8) void {
    const stdStr = str.makeRuntime(string);
    if (mode == OutputMode.Serial) {
        serial.writeString(stdStr);
    } else if (mode == OutputMode.VgaText) {
        vgaTxt.printStr(stdStr);
    } else if (mode == OutputMode.Graphics) {
        term.putString(stdStr);
        term.refresh();
    }
}

pub fn printchar(chr: str.char) void {
    if (mode == OutputMode.Serial) {
        serial.writeChar(chr);
    } else if (mode == OutputMode.VgaText) {
        vgaTxt.putChar(chr);
    } else if (mode == OutputMode.Graphics) {
        term.putChar(chr);
        term.refresh();
    }
}

pub fn println(string: []const u8) void {
    const stdStr = str.makeRuntime(string);
    if (mode == OutputMode.Serial) {
        serial.writeString(stdStr);
        serial.writeString(str.make("\n"));
    } else if (mode == OutputMode.VgaText) {
        vgaTxt.printStr(stdStr);
        vgaTxt.printStr(str.make("\n"));
    } else if (mode == OutputMode.Graphics) {
        term.putString(stdStr);
        term.putString(str.make("\n"));
        term.refresh();
    }
}

pub fn setCursorPos(x: u8, y: u8) void {
    if (mode == OutputMode.VgaText) {
        vgaTxt.setCursorPos(x, y);
    } else if (mode == OutputMode.Graphics) {
        term.setCursorPosition(x, y);
        term.refresh();
    }
}

pub fn printU64(num: u64) void {
    @setRuntimeSafety(false);
    var buffer: [20]u8 = undefined;
    var i: usize = buffer.len;
    var v = num;

    if (v == 0) {
        char('0');
        return;
    }

    while (v != 0) : (i -= 1) {
        const digit = @as(u8, @intCast(v % 10));
        buffer[i - 1] = '0' + digit;
        v /= 10;
    }

    const length = buffer.len - i;

    for (0..length) |j| {
        char(buffer[i + j]);
    }
}

pub fn printn(num: u32) void {
    @setRuntimeSafety(false);
    var buffer: [20]u8 = undefined;
    var i: usize = buffer.len;
    var v = num;

    if (v == 0) {
        char('0');
        return;
    }

    while (v != 0) : (i -= 1) {
        const digit = @as(u8, @intCast(v % 10));
        buffer[i - 1] = '0' + digit;
        v /= 10;
    }

    const length = buffer.len - i;

    for (0..length) |j| {
        char(buffer[i + j]);
    }
}

pub fn printHex(num: u64) void {
    @setRuntimeSafety(false);
    print("0x");
    var buffer: [16]u8 = undefined;
    var i: usize = buffer.len;
    var v = num;

    if (v == 0) {
        char('0');
        return;
    }

    while (v != 0) : (i -= 1) {
        const digit = @as(u8, @intCast(v % 16));
        buffer[i - 1] = if (digit < 10) '0' + digit else 'A' + digit - 10;
        v /= 16;
    }

    const length = buffer.len - i;

    for (0..length) |j| {
        char(buffer[i + j]);
    }
}

pub fn printstr(string: str.String) void {
    if (mode == OutputMode.Serial) {
        serial.writeString(string);
    } else if (mode == OutputMode.VgaText) {
        vgaTxt.printStr(string);
    } else if (mode == OutputMode.Graphics) {
        term.putString(string);
        term.refresh();
    }
}

pub fn setTextColor(fg: VgaTextColor, bg: VgaTextColor) void {
    if (mode == OutputMode.VgaText) {
        vgaTxt.setTextColor(fg, bg);
    } else if (mode == OutputMode.Graphics) {
        term.setColorsFromVga(fg, bg);
        term.refresh();
    }
}
