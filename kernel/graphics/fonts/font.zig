const PsfHeader = struct {
    magic: u32,
    version: u32,
    headersize: u32,
    flags: u32,
    length: u32,
    charsize: u32,
    height: u32,
    width: u32,
};

pub const Font = struct {
    header: PsfHeader,
    glyph_data: [*]const u8,
    unicode_table: ?[*]const u8,

    extern const _binary_kernel_graphics_fonts_aply16_bitfnt_start: u8;
    extern const _binary_kernel_graphics_fonts_aply16_bitfnt_end: u8;
    extern const _binary_kernel_graphics_fonts_aply16_bitfnt_size: u8;

    pub fn init() Font {
        @setRuntimeSafety(false);

        const header_ptr: *const PsfHeader = @ptrCast(@alignCast(&_binary_kernel_graphics_fonts_aply16_bitfnt_start));
        const header: PsfHeader = header_ptr.*;

        if (header.magic != 0x864ab572) {
            @panic("Invalid PSF magic number");
        }

        const glyph_data: [*]const u8 = @ptrFromInt(@intFromPtr(&_binary_kernel_graphics_fonts_aply16_bitfnt_start) + header.headersize);

        var unicode_table: ?[*]const u8 = null;
        if (header.flags & 0x01 != 0) {
            const unicode_offset = header.headersize + (header.length * header.charsize);
            unicode_table = @ptrFromInt(@intFromPtr(&_binary_kernel_graphics_fonts_aply16_bitfnt_start) + unicode_offset);
        }

        return Font{
            .header = header,
            .glyph_data = glyph_data,
            .unicode_table = unicode_table,
        };
    }

    pub fn getGlyph(self: *const Font, codepoint: u32) ?[*]const u8 {
        @setRuntimeSafety(false);

        if (codepoint <= self.header.length) {
            const glyph_offset = codepoint * self.header.charsize;
            return self.glyph_data + glyph_offset;
        }

        // TODO: Handle Unicode codepoints if unicode_table is available

        return null;
    }
};
