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

pub fn println(string: []const u8) void {
    const stdStr = str.makeRuntime(string);
    vgaTxt.printStr(stdStr);
    vgaTxt.printStr(str.make("\n"));
}

pub fn printstr(string: str.String) void {
    vgaTxt.printStr(string);
}

pub fn setTextColor(fg: VgaTextColor, bg: VgaTextColor) void {
    vgaTxt.setTextColor(fg, bg);
}
