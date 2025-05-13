const vgaTxt = @import("../graphics/text_vga.zig");

pub fn clear() void {
    vgaTxt.clear();
}

pub fn initOutputs() void {
    vgaTxt.initVgaText();
}
