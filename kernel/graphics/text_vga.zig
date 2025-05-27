const str = @import("string");
const sys = @import("system");
const mem = @import("memory");

pub var cursor_x: u16 = 0;
pub var cursor_y: u16 = 0;
var attribute: u32 = 0x0F;
var memory_ptr: mem.VolatilePointer(u16) = undefined;

pub const VgaTextColor = enum(u8) {
    Black = 0,
    Blue = 1,
    Green = 2,
    Cyan = 3,
    Red = 4,
    Magenta = 5,
    Brown = 6,
    LightGray = 7,
    DarkGray = 8,
    LightBlue = 9,
    LightGreen = 10,
    LightCyan = 11,
    LightRed = 12,
    Pink = 13,
    Yellow = 14,
    White = 15,
};

fn scroll() void {
    const screen_width = 80;
    const screen_height = 25;

    if (cursor_y >= screen_height) {
        const lines_to_move = screen_height - 1;
        const total_cells = lines_to_move * screen_width;

        const dst = memory_ptr;
        const src = memory_ptr.offset(screen_width);

        _ = sys.memcpy16v(dst.data, src.data, total_cells * @sizeOf(u16));

        const blank: u16 = 0x20 | @as(u16, @intCast(attribute << 8));
        const last_line = memory_ptr.offset((screen_height - 1) * screen_width);
        _ = sys.memset16v(last_line.data, blank, screen_width);

        cursor_y = screen_height - 1;
    }
}

pub fn setCursorPos(x: u8, y: u8) void {
    cursor_x = @intCast(x);
    cursor_y = @intCast(y);
    moveCursor();
}

fn moveCursor() void {
    const temp: u16 = cursor_y * 80 + cursor_x;

    sys.outb(0x3D4, 14);
    sys.outb(0x3D5, @as(u8, @intCast(temp >> 8)));
    sys.outb(0x3D4, 15);
    sys.outb(0x3D5, @as(u8, @intCast(temp & 0xFF)));
}

pub fn clear() void {
    const blank: u16 = 0x20 | @as(u16, @intCast((attribute << 8)));

    for (0..25) |i| {
        const offset = i * 80;
        const ptr = memory_ptr.offset(offset).data;
        _ = sys.memset16v(ptr, blank, 80);
    }

    cursor_x = 0;
    cursor_y = 0;
    moveCursor();
}

pub fn setTextColor(fg: VgaTextColor, bg: VgaTextColor) void {
    attribute = (@intFromEnum(bg) << 4) | (@intFromEnum(fg) & 0x0F);
}

pub fn putChar(char: str.char) void {
    var where: mem.VolatilePointer(u16) = undefined;
    const attr: u16 = @as(u16, @intCast(attribute << 8));

    if (char == 0x08) {
        if (cursor_x != 0) {
            cursor_x -= 1;
            putChar(' ');
            cursor_x -= 1;
        }
    } else if (char == 0x09) {
        cursor_x = (cursor_x + 4) & ~@as(u16, 3);
    } else if (char == '\r') {
        cursor_x = 0;
    } else if (char == '\n') {
        cursor_x = 0;
        cursor_y += 1;
    } else if (char >= ' ') {
        where = memory_ptr.offset(cursor_y * 80 + cursor_x);
        const value: u16 = @as(u16, @intCast(char)) | attr;
        where.set(0, value);
        cursor_x += 1;
    }

    if (cursor_x >= 80) {
        cursor_x = 0;
        cursor_y += 1;
    }

    scroll();
    moveCursor();
}

pub fn printStr(string: str.String) void {
    for (string.iterate()) |c| {
        putChar(c);
    }
}

pub fn initVgaText() void {
    memory_ptr = mem.VolatilePointer(u16).atAddr(0xB8000);
    setTextColor(VgaTextColor.LightGray, VgaTextColor.Black);
}
