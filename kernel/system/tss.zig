const gdt = @import("gdt");

pub const TSS = packed struct {
    link: u16,
    reserved1: u16,
    esp0: u32, // Kernel stack pointer
    ss0: u16, // Kernel stack segment
    reserved2: u16,
    esp1: u32,
    ss1: u16,
    reserved3: u16,
    esp2: u32,
    ss2: u16,
    reserved4: u16,
    cr3: u32,
    eip: u32,
    eflags: u32,
    eax: u32,
    ecx: u32,
    edx: u32,
    ebx: u32,
    esp: u32,
    ebp: u32,
    esi: u32,
    edi: u32,
    es: u16,
    reserved5: u16,
    cs: u16,
    reserved6: u16,
    ss: u16,
    reserved7: u16,
    ds: u16,
    reserved8: u16,
    fs: u16,
    reserved9: u16,
    gs: u16,
    reserved10: u16,
    ldt: u16,
    reserved11: u16,
    trap: u16,
    iomap: u16,
};

var tss: TSS align(16) = undefined;

extern var stack_top: u8;
extern var stack_bottom: u8;

pub inline fn getStackTop() usize {
    @setRuntimeSafety(false);
    return @intFromPtr(&stack_top);
}

pub inline fn getStackBottom() usize {
    @setRuntimeSafety(false);
    return @intFromPtr(&stack_bottom);
}

extern fn memcpy(
    dest: [*]u8,
    src: [*]const u8,
    len: usize,
) [*]u8;

pub fn init() void {
    @setRuntimeSafety(false);
    const zeroes = [_]u8{0} ** @sizeOf(TSS);
    _ = memcpy(@as([*]u8, @ptrCast(&tss))[0..@sizeOf(TSS)], &zeroes, @sizeOf(TSS));
    tss.ss0 = 0x10; // Kernel stack segment
    tss.esp0 = getStackTop();
    tss.iomap = @sizeOf(TSS); // I/O map base address

    const tss_base = @intFromPtr(&tss);
    const tss_limit = @sizeOf(TSS) - 1;

    gdt.setGate(5, tss_base, tss_limit, 0x89, 0x40);
}

pub fn loadTss() void {
    asm volatile ("ltr %[tss_selector]"
        :
        : [tss_selector] "r" (@as(u16, 0x28)),
    );
}
