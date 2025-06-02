const out = @import("output");
const alloc = @import("allocator");
const vfs = @import("vfs");
const ata = @import("ata");
const terminal = @import("terminal");
const mem = @import("memory");

export fn syscall_handler(
    _: u32,
    _: u32,
    _: u32,
    _: u32,
    _: u32,
    _: u32,
) u64 {
    @setRuntimeSafety(false);
    return 0;
}
