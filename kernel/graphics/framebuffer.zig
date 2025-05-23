const mutltiboot2 = @import("multiboot2");
const sys = @import("system");
const out = @import("output");
const virtmem = @import("virtual_mem");

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub fn from(r: u8, g: u8, b: u8) Color {
        return Color{ .r = r, .g = g, .b = b };
    }

    pub fn setAlpha(self: *const Color, alpha: u8) void {
        self.a = alpha;
    }
};

pub const Position = struct {
    x: u32,
    y: u32,

    pub fn from(x: u32, y: u32) Position {
        return Position{ .x = x, .y = y };
    }
};

pub const Framebuffer = struct {
    framebufferTag: mutltiboot2.FramebufferTag,
    framebuffer_addr: u32,

    pub fn init(framebufferTag: mutltiboot2.FramebufferTag) Framebuffer {
        @setRuntimeSafety(false);
        const virtAddr = virtmem.identityMap(@as(usize, @intCast(framebufferTag.addr)), framebufferTag.pitch * framebufferTag.height);
        return Framebuffer{
            .framebufferTag = framebufferTag,
            .framebuffer_addr = virtAddr,
        };
    }

    pub fn drawPixel(self: *const Framebuffer, x: u32, y: u32, color: Color) void {
        const fb = self.framebufferTag;

        if (x >= fb.width or y >= fb.height) {
            return;
        }

        const bytes_per_pixel = fb.bpp / 8;
        const pixel_offset = y * fb.pitch + x * bytes_per_pixel;
        const framebuffer_addr = self.framebuffer_addr + pixel_offset;

        const pixel_ptr: [*]u8 = @ptrFromInt(framebuffer_addr);
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

    pub fn drawLineAccrossScreen(self: *const Framebuffer) void {
        const fb = self.framebufferTag;
        var x: u32 = 0;
        while (x < fb.width) : (x += 1) {
            self.drawPixel(x, fb.height / 2, Color.from(255, 0, 0));
        }
    }

    pub fn drawRect(self: *const Framebuffer, pos: Position, width: u32, height: u32, color: Color) void {
        var x: u32 = pos.x;
        var y: u32 = pos.y;

        while (y < height) : (y += 1) {
            while (x < width) : (x += 1) {
                self.drawPixel(x, y, color);
            }
            x = pos.x;
        }
    }

    pub fn fill(self: *const Framebuffer, color: Color) void {
        const fb = self.framebufferTag;
        var x: u32 = 0;
        var y: u32 = 0;

        while (y < fb.height) : (y += 1) {
            while (x < fb.width) : (x += 1) {
                self.drawPixel(x, y, color);
            }
            x = 0;
        }
    }

    pub fn getWidth(self: *const Framebuffer) u32 {
        return self.framebufferTag.width;
    }

    pub fn getHeight(self: *const Framebuffer) u32 {
        return self.framebufferTag.height;
    }

    pub fn drawCircle(self: *const Framebuffer, center: Position, radius: u32, color: Color) void {
        var x: i32 = 0;
        var y: i32 = @intCast(radius);
        var d: i32 = 1 - @as(i32, @intCast(radius));

        while (x <= y) : (x += 1) {
            self.drawPixel(center.x + x, center.y + y, color);
            self.drawPixel(center.x - x, center.y + y, color);
            self.drawPixel(center.x + x, center.y - y, color);
            self.drawPixel(center.x - x, center.y - y, color);
            self.drawPixel(center.x + y, center.y + x, color);
            self.drawPixel(center.x - y, center.y + x, color);
            self.drawPixel(center.x + y, center.y - x, color);
            self.drawPixel(center.x - y, center.y - x, color);

            if (d < 0) {
                d += 2 * x + 3;
            } else {
                d += 2 * (x - y) + 5;
                y -= 1;
            }
        }
    }
};
