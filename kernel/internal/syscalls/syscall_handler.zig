const out = @import("output");

export fn syscall_handler(
    _: u32,
    _: u32,
    _: u32,
    _: u32,
    _: u32,
    _: u32,
) u64 {
    @setRuntimeSafety(false);
    out.print("System call handler invoked.\n");
    return 0;
}
