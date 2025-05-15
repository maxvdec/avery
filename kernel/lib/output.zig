const vgaTxt = @import("text_vga");
const str = @import("string");
const output = @import("system");

pub const VgaTextColor = vgaTxt.VgaTextColor;

pub fn clear() void {
    vgaTxt.clear();
}

pub fn initOutputs() void {
    vgaTxt.initVgaText();
}

pub fn char(chr: str.char) void {
    vgaTxt.putChar(chr);
}

pub fn print(string: []const u8) void {
    const stdStr = str.makeRuntime(string);
    vgaTxt.printStr(stdStr);
}

pub fn printchar(chr: str.char) void {
    vgaTxt.putChar(chr);
}

pub fn println(string: []const u8) void {
    const stdStr = str.makeRuntime(string);
    vgaTxt.printStr(stdStr);
    vgaTxt.printStr(str.make("\n"));
}

pub fn printU64(num: u64) void {
    @setRuntimeSafety(false);
    var buffer: [20]u8 = undefined;
    var i: usize = buffer.len;
    var v = num;

    if (v == 0) {
        vgaTxt.putChar('0');
        return;
    }

    while (v != 0) : (i -= 1) {
        const digit = @as(u8, @intCast(v % 10));
        buffer[i - 1] = '0' + digit;
        v /= 10;
    }

    const length = buffer.len - i;

    for (0..length) |j| {
        vgaTxt.putChar(buffer[i + j]);
    }
}

pub fn printHex(num: u64) void {
    @setRuntimeSafety(false);
    var buffer: [16]u8 = undefined;
    var i: usize = buffer.len;
    var v = num;

    if (v == 0) {
        vgaTxt.putChar('0');
        return;
    }

    while (v != 0) : (i -= 1) {
        const digit = @as(u8, @intCast(v % 16));
        buffer[i - 1] = if (digit < 10) '0' + digit else 'A' + digit - 10;
        v /= 16;
    }

    const length = buffer.len - i;

    for (0..length) |j| {
        vgaTxt.putChar(buffer[i + j]);
    }
}

pub fn printstr(string: str.String) void {
    vgaTxt.printStr(string);
}

pub fn setTextColor(fg: VgaTextColor, bg: VgaTextColor) void {
    vgaTxt.setTextColor(fg, bg);
}
