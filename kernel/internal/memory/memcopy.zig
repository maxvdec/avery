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
