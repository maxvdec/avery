pub fn memcpy(dst: [*]u8, src: [*]u8, count: usize) [*]u8 {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        dst[i] = src[i];
    }
    return dst;
}

pub fn memcpyv(dst: [*]volatile u8, src: [*]volatile u8, count: usize) [*]volatile u8 {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        dst[i] = src[i];
    }
    return dst;
}

pub fn memset(dst: [*]u8, value: u8, count: usize) [*]u8 {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        dst[i] = value;
    }
    return dst;
}

pub fn memsetv(dst: [*]volatile u8, value: u8, count: usize) [*]volatile u8 {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        dst[i] = value;
    }
    return dst;
}

pub fn memset16v(dst: [*]volatile u16, value: u16, count: usize) [*]volatile u16 {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        dst[i] = value;
    }
    return dst;
}

pub fn memset16(dst: [*]u16, value: u16, count: usize) [*]u16 {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        dst[i] = value;
    }
    return dst;
}

pub fn inb(port: u16) u8 {
    var result: u8 = undefined;
    asm volatile (
        \\ inb %dx, %al
        : [_] "={al}" (result),
        : [_] "{dx}" (port),
        : "volatile"
    );
    return result;
}

pub fn outb(port: u16, value: u8) void {
    asm volatile (
        \\ outb %al, %dx
        :
        : [_] "{dx}" (port),
          [_] "{al}" (value),
        : "volatile"
    );
}
