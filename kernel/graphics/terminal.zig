const mem = @import("memory");
const font = @import("font");
const Framebuffer = @import("framebuffer").Framebuffer;
const Color = @import("framebuffer").Color;
const out = @import("output");
const Position = @import("framebuffer").Position;
const str = @import("string");

pub const FramebufferTerminal = struct {
    font: *const font.Font,
    framebuffer: *const Framebuffer,
    cursor_x: u32,
    cursor_y: u32,
    max_cols: u32,
    max_rows: u32,
    fg_color: Color,
    bg_color: Color,
    cursor_visible: bool,
    totally_visible: bool,
    cursor_blink_counter: u32,
    cursor_blink_rate: u32,

    const CURSOR_BLINK_RATE = 15;

    pub fn init(framebuffer: *const Framebuffer, terminal_font: *const font.Font) FramebufferTerminal {
        const font_width = terminal_font.header.width;
        const font_height = terminal_font.header.height;
        const max_cols = framebuffer.framebufferTag.width / font_width;
        const max_rows = framebuffer.framebufferTag.height / font_height;

        return FramebufferTerminal{
            .font = terminal_font,
            .framebuffer = framebuffer,
            .cursor_x = 0,
            .cursor_y = 0,
            .max_cols = max_cols,
            .max_rows = max_rows,
            .fg_color = Color.from(211, 211, 211),
            .bg_color = Color.from(0, 0, 0),
            .cursor_visible = true,
            .totally_visible = true,
            .cursor_blink_counter = 0,
            .cursor_blink_rate = CURSOR_BLINK_RATE,
        };
    }

    pub fn clear(self: *FramebufferTerminal) void {
        self.framebuffer.fillScreen(self.bg_color);
        self.cursor_x = 0;
        self.cursor_y = 0;
    }

    pub fn setCursorPosition(self: *FramebufferTerminal, x: u32, y: u32) void {
        self.cursor_x = if (x >= self.max_cols) self.max_cols - 1 else x;
        self.cursor_y = if (y >= self.max_rows) self.max_rows - 1 else y;
    }

    pub fn getCursorPosition(self: *const FramebufferTerminal) struct { x: u32, y: u32 } {
        return .{ .x = self.cursor_x, .y = self.cursor_y };
    }

    pub fn setColors(self: *FramebufferTerminal, fg: Color, bg: Color) void {
        self.fg_color = fg;
        self.bg_color = bg;
    }

    pub fn setColorsFromVga(self: *FramebufferTerminal, fg: out.VgaTextColor, bg: out.VgaTextColor) void {
        const fgData = Color.fromVga(fg);
        const bgData = Color.fromVga(bg);
        self.fg_color = Color.from(fgData[0], fgData[1], fgData[2]);
        self.bg_color = Color.from(bgData[0], bgData[1], bgData[2]);
    }

    fn newline(self: *FramebufferTerminal) void {
        self.cursor_x = 0;
        self.cursor_y += 1;

        if (self.cursor_y >= self.max_rows) {
            self.scroll();
            self.cursor_y = self.max_rows - 1;
        }
    }

    fn scroll(self: *FramebufferTerminal) void {
        @setRuntimeSafety(false);
        const font_height = self.font.header.height;
        const fb = self.framebuffer.framebufferTag;
        const scroll_height = font_height;

        const src_y = scroll_height;
        const dst_y = 0;
        const copy_height = fb.height - scroll_height;

        var y: u32 = 0;
        while (y < copy_height) : (y += 1) {
            const src_offset = ((src_y + y) * fb.pitch);
            const dst_offset = ((dst_y + y) * fb.pitch);
            const src_ptr = self.framebuffer.backbuffer + src_offset;
            const dst_ptr = self.framebuffer.backbuffer + dst_offset;

            var x: u32 = 0;
            while (x < fb.pitch) : (x += 1) {
                dst_ptr[x] = src_ptr[x];
            }
        }

        self.clearLine(self.max_rows - 1);
    }

    fn clearLine(self: *FramebufferTerminal, line: u32) void {
        const font_height = self.font.header.height;
        const start_y = line * font_height;

        var y: u32 = 0;
        while (y < font_height) : (y += 1) {
            var x: u32 = 0;
            while (x < self.framebuffer.framebufferTag.width) : (x += 1) {
                self.framebuffer.drawPixel(Position.from(x, start_y + y), self.bg_color);
            }
        }
    }

    fn tab(self: *FramebufferTerminal) void {
        const tab_size = 4;
        const spaces_to_next_tab = tab_size - (self.cursor_x % tab_size);
        var i: u32 = 0;
        while (i < spaces_to_next_tab) : (i += 1) {
            self.putChar(' ');
        }
    }

    fn backspace(self: *FramebufferTerminal) void {
        if (self.cursor_x > 0) {
            self.cursor_x -= 1;
            self.drawCharAtCursor(' ');
        } else if (self.cursor_y > 0) {
            self.cursor_y -= 1;
            self.cursor_x = self.max_cols - 1;
        }
    }

    fn drawCharAtCursor(self: *const FramebufferTerminal, char: u8) void {
        const pixel_x = self.cursor_x * self.font.header.width;
        const pixel_y = self.cursor_y * self.font.header.height;

        out.print("Drawing char at position: ");
        out.printn(self.cursor_x);
        out.print(", ");
        out.printn(self.cursor_y);
        out.print("\n");
        self.framebuffer.drawChar(Position.from(pixel_x, pixel_y), self.font, char, self.fg_color, self.bg_color);
    }

    pub fn putChar(self: *FramebufferTerminal, char: u8) void {
        switch (char) {
            '\n' => self.newline(),
            '\r' => self.cursor_x = 0,
            '\t' => self.tab(),
            '\x08' => self.backspace(),
            0x7F => self.backspace(),
            ' '...0x7E => {
                self.drawCharAtCursor(char);
                self.cursor_x += 1;
                if (self.cursor_x >= self.max_cols) {
                    self.newline();
                }
            },
            else => {
                self.drawCharAtCursor('?');
                self.cursor_x += 1;
                if (self.cursor_x >= self.max_cols) {
                    self.newline();
                }
            },
        }
    }

    pub fn putString(self: *FramebufferTerminal, string: []const u8) void {
        for (string) |char| {
            self.putChar(char);
        }
        self.refresh();
    }

    pub fn hideCursor(self: *FramebufferTerminal) void {
        self.clearCursorArea();
        self.totally_visible = false;
    }

    pub fn displayCursor(self: *FramebufferTerminal) void {
        self.totally_visible = true;
        self.cursor_visible = true;
        self.drawCursor();
    }

    fn drawCursor(self: *const FramebufferTerminal) void {
        if (!self.cursor_visible or !self.totally_visible) return;

        const pixel_x = self.cursor_x * self.font.header.width;
        const pixel_y = self.cursor_y * self.font.header.height;
        const cursor_width = 2;

        var y: u32 = 0;
        while (y < self.font.header.height) : (y += 1) {
            var x: u32 = 0;
            while (x < cursor_width and pixel_x + x < self.framebuffer.framebufferTag.width) : (x += 1) {
                self.framebuffer.drawPixel(Position.from(pixel_x + x, pixel_y + y), self.fg_color);
            }
        }
    }

    fn clearCursorArea(self: *const FramebufferTerminal) void {
        const pixel_x = self.cursor_x * self.font.header.width;
        const pixel_y = self.cursor_y * self.font.header.height;
        const cursor_width = 2;

        var y: u32 = 0;
        while (y < self.font.header.height) : (y += 1) {
            var x: u32 = 0;
            while (x < cursor_width and pixel_x + x < self.framebuffer.framebufferTag.width) : (x += 1) {
                self.framebuffer.drawPixel(Position.from(pixel_x + x, pixel_y + y), self.bg_color);
            }
        }
    }

    pub fn updateCursor(self: *FramebufferTerminal) void {
        self.cursor_blink_counter += 1;

        if (self.cursor_blink_counter >= self.cursor_blink_rate) {
            self.cursor_blink_counter = 0;

            if (self.cursor_visible) {
                self.clearCursorArea();
                self.cursor_visible = false;
            } else {
                self.drawCursor();
                self.cursor_visible = true;
            }
        }
        self.refresh();
    }

    pub fn showCursor(self: *FramebufferTerminal, show: bool) void {
        if (!show and self.cursor_visible) {
            self.clearCursorArea();
        }
        self.cursor_visible = show;
        if (show) {
            self.drawCursor();
        }
    }

    pub fn refresh(self: *const FramebufferTerminal) void {
        if (self.cursor_visible) {
            self.drawCursor();
        }
        self.framebuffer.presentBackbuffer();
    }

    pub fn getMaxColumns(self: *const FramebufferTerminal) u32 {
        return self.max_cols;
    }

    pub fn getMaxRows(self: *const FramebufferTerminal) u32 {
        return self.max_rows;
    }

    pub fn moveCursorUp(self: *FramebufferTerminal) void {
        if (self.cursor_y > 0) {
            self.cursor_y -= 1;
        }
    }

    pub fn moveCursorDown(self: *FramebufferTerminal) void {
        if (self.cursor_y < self.max_rows - 1) {
            self.cursor_y += 1;
        }
    }

    pub fn moveCursorLeft(self: *FramebufferTerminal) void {
        if (self.cursor_x > 0) {
            self.cursor_x -= 1;
        }
    }

    pub fn moveCursorRight(self: *FramebufferTerminal) void {
        if (self.cursor_x < self.max_cols - 1) {
            self.cursor_x += 1;
        }
    }
};
