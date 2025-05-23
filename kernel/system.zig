pub fn memcpyv(dst: [*]volatile u8, src: [*]volatile u8, count: usize) [*]volatile u8 {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        dst[i] = src[i];
    }
    return dst;
}

pub fn memcpy16v(dst: [*]volatile u16, src: [*]volatile u16, count: usize) [*]volatile u16 {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        dst[i] = src[i];
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
    @setRuntimeSafety(false);
    var result: u8 = undefined;
    asm volatile (
        \\ inb %dx, %al
        : [_] "={al}" (result),
        : [_] "{dx}" (port),
        : "volatile"
    );
    return result;
}

pub fn inw(port: u16) u16 {
    @setRuntimeSafety(false);
    var value: u16 = 0;
    asm volatile (
        \\ inw %dx, %ax
        : [_] "={ax}" (value),
        : [_] "{dx}" (port),
        : "volatile"
    );
    return value;
}

pub fn outb(port: u16, value: u8) void {
    @setRuntimeSafety(false);
    asm volatile (
        \\ outb %al, %dx
        :
        : [_] "{dx}" (port),
          [_] "{al}" (value),
        : "volatile"
    );
}

pub fn outw(port: u16, value: u16) void {
    @setRuntimeSafety(false);
    asm volatile (
        \\ outw %ax, %dx
        :
        : [_] "{dx}" (port),
          [_] "{ax}" (value),
        : "volatile"
    );
}

pub const regs = packed struct {
    gs: u32,
    fs: u32,
    es: u32,
    ds: u32,
    edi: u32,
    esi: u32,
    ebp: u32,
    esp: u32,
    ebx: u32,
    edx: u32,
    ecx: u32,
    eax: u32,
    int_no: u32,
    err_code: u32,
    eip: u32,
    cs: u32,
    eflags: u32,
    useresp: u32,
    ss: u32,
};

pub fn panic(msg: []const u8) noreturn {
    @setRuntimeSafety(false);
    const out = @import("output");
    out.setTextColor(out.VgaTextColor.White, out.VgaTextColor.Red);
    out.clear();
    out.println("The Avery Kernel panicked!\n");
    out.println(msg);
    out.print("\n");
    out.println("The computer ran into a problem it could not recover from.");
    out.println("Please report this to the developers.\n");
    while (true) {}
}

pub fn delay(iterations: u64) void {
    var i: u64 = 0;
    while (i < iterations) : (i += 1) {
        asm volatile ("nop");
    }
}
