const out = @import("output");
const isr = @import("isr");

const regs = packed struct {
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

export fn fault_handler(r: *regs) callconv(.C) noreturn {
    @setRuntimeSafety(false);
    out.initOutputs();
    out.setTextColor(out.VgaTextColor.White, out.VgaTextColor.Red);
    out.clear();
    out.println("The Avery Kernel panicked!");
    out.printstr(isr.EXCEPTION_MESSAGES[r.int_no]);
    out.print("\n");
    out.println("The computer ran into a problem it could not recover from.");
    out.println("Please report this to the developers.\n");
    out.print("Error code: ");
    out.printHex(r.int_no);
    out.print("\n");
    if (r.int_no == 0x0E) {
        out.print("Key-code: ");
        out.printHex(r.err_code);
        out.print("\n");
    }

    while (true) {}
}
