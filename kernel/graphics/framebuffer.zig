const multiboot2 = @import("multiboot2");
const sys = @import("system");
const out = @import("output");
const virtmem = @import("virtual_mem");
const alloc = @import("allocator");
const pmm = @import("physical_mem");
const font = @import("font");

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub fn from(r: u8, g: u8, b: u8) Color {
        return Color{ .r = r, .g = g, .b = b, .a = 255 };
    }

    pub fn setAlpha(self: *Color, alpha: u8) void {
        self.a = alpha;
    }

    pub fn fromVga(color: out.VgaTextColor) [3]u8 {
        @setRuntimeSafety(false);
        switch (color) {
            .Black => return [3]u8{ 0, 0, 0 },
            .Blue => return [3]u8{ 0, 0, 255 },
            .Green => return [3]u8{ 0, 255, 0 },
            .Cyan => return [3]u8{ 0, 255, 255 },
            .Red => return [3]u8{ 255, 0, 0 },
            .Magenta => return [3]u8{ 255, 0, 255 },
            .Brown => return [3]u8{ 165, 42, 42 },
            .LightGray => return [3]u8{ 211, 211, 211 },
            .DarkGray => return [3]u8{ 169, 169, 169 },
            .LightBlue => return [3]u8{ 173, 216, 230 },
            .LightGreen => return [3]u8{ 144, 238, 144 },
            .LightCyan => return [3]u8{ 224, 255, 255 },
            .LightRed => return [3]u8{ 255, 182, 193 },
            .Pink => return [3]u8{ 255, 192, 203 },
            .Yellow => return [3]u8{ 255, 255, 0 },
            .White => return [3]u8{ 255, 255, 255 },
        }
    }

    pub fn equals(self: Color, other: Color) bool {
        return self.r == other.r and self.g == other.g and self.b == other.b and self.a == other.a;
    }
};

pub const Position = struct {
    x: u32,
    y: u32,

    pub fn from(x: u32, y: u32) Position {
        return Position{ .x = x, .y = y };
    }
};

extern fn memcpy(dest: [*]u8, src: [*]u8, size: usize) [*]u8;

pub const Framebuffer = struct {
    framebufferTag: multiboot2.FramebufferTag,
    framebuffer_addr: u32,
    backbuffer: [*]u8 = undefined,

    pub fn init(framebufferTag: multiboot2.FramebufferTag) Framebuffer {
        @setRuntimeSafety(false);
        const framebufferSize = framebufferTag.pitch * framebufferTag.height;

        const virtFramebufferAddr = virtmem.mapKernelMemory(@as(usize, @intCast(framebufferTag.addr)), framebufferSize);

        const backbufferVirtAddr = virtmem.allocVirtual(framebufferSize, virtmem.PAGE_PRESENT | virtmem.PAGE_RW) orelse {
            sys.panic("Failed to allocate virtual memory for framebuffer backbuffer");
        };

        const backbufferSlice: [*]u8 = @ptrFromInt(backbufferVirtAddr);
        for (0..framebufferSize) |i| {
            backbufferSlice[i] = 0;
        }

        return Framebuffer{
            .framebufferTag = framebufferTag,
            .framebuffer_addr = virtFramebufferAddr,
            .backbuffer = backbufferSlice,
        };
    }

    pub fn presentBackbuffer(self: *const Framebuffer) void {
        @setRuntimeSafety(false);

        const framebuffer_ptr: [*]u8 = @ptrFromInt(self.framebuffer_addr);
        const framebufferSize = self.framebufferTag.pitch * self.framebufferTag.height;

        _ = memcpy(framebuffer_ptr, self.backbuffer, framebufferSize);
    }

    pub fn drawPixel(self: *const Framebuffer, pos: Position, color: Color) void {
        @setRuntimeSafety(false);

        const fb = self.framebufferTag;

        if (pos.x >= fb.width or pos.y >= fb.height) {
            return;
        }

        const bytes_per_pixel = fb.bpp / 8;
        const pixel_offset = (pos.y * fb.pitch) + (pos.x * bytes_per_pixel);

        const pixel_ptr: [*]u8 = self.backbuffer + pixel_offset;
        switch (fb.bpp) {
            32 => {
                if (fb.framebuffer_type == 1) {
                    pixel_ptr[0] = color.b;
                    pixel_ptr[1] = color.g;
                    pixel_ptr[2] = color.r;
                    pixel_ptr[3] = color.a;
                } else {
                    const pixel_value = (@as(u32, color.r) << 16) |
                        (@as(u32, color.g) << 8) |
                        @as(u32, color.b);
                    const pixel_ptr_u32: *u32 = @ptrCast(@alignCast(pixel_ptr));
                    pixel_ptr_u32.* = pixel_value;
                }
            },
            24 => {
                pixel_ptr[0] = color.r;
                pixel_ptr[1] = color.g;
                pixel_ptr[2] = color.b;
            },
            16 => {
                const r5 = @as(u16, color.r >> 3);
                const g6 = @as(u16, color.g >> 2);
                const b5 = @as(u16, color.b >> 3);

                const pixel_value = (r5 << 11) | (g6 << 5) | b5;
                const pixel_ptr_u16: *u16 = @ptrCast(@alignCast(pixel_ptr));
                pixel_ptr_u16.* = pixel_value;
            },
            8 => {},
            else => {
                return;
            },
        }
    }

    pub fn drawToFrontbuffer(self: *const Framebuffer, pos: Position, color: Color) void {
        @setRuntimeSafety(false);

        const fb = self.framebufferTag;

        if (pos.x >= fb.width or pos.y >= fb.height) {
            return;
        }

        const bytes_per_pixel = fb.bpp / 8;
        const pixel_offset = (pos.y * fb.pitch) + (pos.x * bytes_per_pixel);

        const framebuffer_ptr: [*]u8 = @ptrFromInt(self.framebuffer_addr);
        const pixel_ptr: [*]u8 = framebuffer_ptr + pixel_offset;
        switch (fb.bpp) {
            32 => {
                if (fb.framebuffer_type == 1) {
                    pixel_ptr[0] = color.b;
                    pixel_ptr[1] = color.g;
                    pixel_ptr[2] = color.r;
                    pixel_ptr[3] = color.a;
                } else {
                    const pixel_value = (@as(u32, color.r) << 16) |
                        (@as(u32, color.g) << 8) |
                        @as(u32, color.b);
                    const pixel_ptr_u32: *u32 = @ptrCast(@alignCast(pixel_ptr));
                    pixel_ptr_u32.* = pixel_value;
                }
            },
            24 => {
                pixel_ptr[0] = color.r;
                pixel_ptr[1] = color.g;
                pixel_ptr[2] = color.b;
            },
            16 => {
                const r5 = @as(u16, color.r >> 3);
                const g6 = @as(u16, color.g >> 2);
                const b5 = @as(u16, color.b >> 3);

                const pixel_value = (r5 << 11) | (g6 << 5) | b5;
                const pixel_ptr_u16: *u16 = @ptrCast(@alignCast(pixel_ptr));
                pixel_ptr_u16.* = pixel_value;
            },
            8 => {},
            else => {
                return;
            },
        }
    }

    pub fn drawTestLine(self: *const Framebuffer) void {
        const fb = self.framebufferTag;
        var x: u32 = 0;
        while (x < fb.width) : (x += 1) {
            self.drawPixel(Position.from(x, fb.height / 2), Color.from(255, 0, 0));
        }
        self.presentBackbuffer();
    }

    pub fn getColorAtPosition(self: *const Framebuffer, pos: Position) Color {
        @setRuntimeSafety(false);

        const fb = self.framebufferTag;

        if (pos.x >= fb.width or pos.y >= fb.height) {
            return Color.from(0, 0, 0);
        }

        const bytes_per_pixel = fb.bpp / 8;
        const pixel_offset = (pos.y * fb.pitch) + (pos.x * bytes_per_pixel);

        const pixel_ptr: [*]u8 = self.backbuffer + pixel_offset;

        switch (fb.bpp) {
            32 => {
                if (fb.framebuffer_type == 1) {
                    return Color{
                        .r = pixel_ptr[2],
                        .g = pixel_ptr[1],
                        .b = pixel_ptr[0],
                        .a = pixel_ptr[3],
                    };
                } else {
                    const pixel_ptr_u32: *u32 = @ptrCast(@alignCast(pixel_ptr));
                    const pixel_value = pixel_ptr_u32.*;
                    return Color{
                        .r = @intCast((pixel_value >> 16) & 0xFF),
                        .g = @intCast((pixel_value >> 8) & 0xFF),
                        .b = @intCast(pixel_value & 0xFF),
                        .a = 255,
                    };
                }
            },
            24 => {
                return Color{
                    .r = pixel_ptr[0],
                    .g = pixel_ptr[1],
                    .b = pixel_ptr[2],
                    .a = 255,
                };
            },
            16 => {
                const pixel_ptr_u16: *u16 = @ptrCast(@alignCast(pixel_ptr));
                const pixel_value = pixel_ptr_u16.*;

                const r5 = (pixel_value >> 11) & 0x1F;
                const g6 = (pixel_value >> 5) & 0x3F;
                const b5 = pixel_value & 0x1F;

                return Color{
                    .r = @intCast(r5 << 3),
                    .g = @intCast(g6 << 2),
                    .b = @intCast(b5 << 3),
                    .a = 255,
                };
            },
            8 => {
                return Color.from(0, 0, 0);
            },
            else => {
                return Color.from(0, 0, 0);
            },
        }
    }

    pub fn fillScreen(self: *const Framebuffer, color: Color) void {
        @setRuntimeSafety(false);

        const fb = self.framebufferTag;
        const total_pixels = fb.width * fb.height;

        for (0..total_pixels) |i| {
            const x = i % fb.width;
            const y = i / fb.width;
            if (self.getColorAtPosition(Position.from(x, y)).equals(color)) continue;
            self.drawPixel(Position.from(x, y), color);
        }

        self.presentBackbuffer();
    }

    pub fn drawChar(self: *const Framebuffer, pos: Position, fnt: *const font.Font, char_code: u32, fg_color: Color, bg_color: ?Color) void {
        @setRuntimeSafety(false);
        if (char_code == 0) return;

        const glyph_data = fnt.getGlyph(char_code) orelse return;
        const font_width = fnt.header.width;
        const font_height = fnt.header.height;

        var y: u32 = 0;
        while (y < font_height) : (y += 1) {
            const bytes_per_row = (font_width + 7) / 8;
            const row_offset = y * bytes_per_row;

            var x: u32 = 0;
            while (x < font_width) : (x += 1) {
                const byte_index = row_offset + (x / 8);
                const bit_index = 7 - (x % 8);
                const pixel_set = (glyph_data[byte_index] >> @intCast(bit_index)) & 1;

                const pixel_pos = Position.from(pos.x + x, pos.y + y);

                if (bg_color) |bg| {
                    self.drawToFrontbuffer(pixel_pos, bg);
                    self.drawPixel(pixel_pos, bg);
                }

                if (pixel_set == 1) {
                    self.drawToFrontbuffer(pixel_pos, fg_color);
                    self.drawPixel(pixel_pos, fg_color);
                }
            }
        }
    }
};
