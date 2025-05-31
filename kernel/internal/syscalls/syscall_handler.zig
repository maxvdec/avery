const out = @import("output");

export fn syscall_handler(
    syscall_number: u32,
    _: u32,
    _: u32,
    _: u32,
    _: u32,
    _: u32,
) u64 {
    @setRuntimeSafety(false);
    out.switchToSerial();
    out.print("Syscall number: ");
    out.printHex(syscall_number);
    out.print("\n");
    return 0;
}
