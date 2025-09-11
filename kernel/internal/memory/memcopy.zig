export fn memset(dst: [*]u8, value: u8, count: usize) [*]u8 {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        dst[i] = value;
    }
    return dst;
}

export fn memcpy(dst: [*]u8, src: [*]const u8, count: usize) [*]u8 {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        dst[i] = src[i];
    }
    return dst;
}

export fn memmove(dst: [*]u8, src: [*]const u8, count: usize) [*]u8 {
    if (count == 0) return dst;

    const dst_addr = @intFromPtr(dst);
    const src_addr = @intFromPtr(src);

    if (dst_addr < src_addr) {
        var i: usize = 0;
        while (i < count) : (i += 1) {
            dst[i] = src[i];
        }
    } else if (dst_addr > src_addr) {
        var i: usize = count;
        while (i > 0) {
            i -= 1;
            dst[i] = src[i];
        }
    }

    return dst;
}
