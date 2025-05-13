const str = @import("../lib/string.zig");
const sys = @import("../system.zig");
const mem = @import("../lib/memory.zig");

var cursor_x: u16 = 0;
var cursor_y: u16 = 0;
const ATTRIBUTE = 0x0F;
var memory_ptr: mem.Pointer(u16) = undefined;

fn scroll() void {
    var blank: u32 = undefined;
    var temp: u32 = undefined;

    blank = 0x20 | (ATTRIBUTE << 8);

    if (cursor_y >= 25) {
        temp = cursor_y - 25 + 1;
        sys.memcpy(&memory_ptr[0], &memory_ptr[temp * 80], (25 - temp) * 80 * 2);
        sys.memset16(&memory_ptr[(25 - temp) * 80], blank, 80);
        cursor_x = 25 - 1;
    }
}

fn moveCursor() void {
    const temp: u16 = cursor_y * 80 + cursor_x;

    sys.outb(0x3D4, 14);
    sys.outb(0x3D5, @as(u8, @intCast(temp >> 8)));
    sys.outb(0x3D4, 15);
    sys.outb(0x3D5, @as(u8, @intCast(temp & 0xFF)));
}

pub fn clear() void {
    var blank: u16 = undefined;

    blank = 0x20 | (ATTRIBUTE << 8);

    for (0..25) |i| {
        const offset = i * 80;
        const ptr = memory_ptr.offset(offset).offsetPtr(80);
        _ = sys.memset16(ptr, blank, 80);
    }

    cursor_x = 0;
    cursor_y = 0;
    moveCursor();
}

pub fn initVgaText() void {
    memory_ptr = memory_ptr.point(0xB8000);
}
