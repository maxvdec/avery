const out = @import("output");
const isr = @import("isr");
const time = @import("time");

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

fn delay(iterations: u64) void {
    var i: u64 = 0;
    while (i < iterations) : (i += 1) {
        asm volatile ("nop");
    }
}

export fn fault_handler(r: *regs) callconv(.C) noreturn {
    @setRuntimeSafety(false);
    out.initOutputs();
    out.switchToSerial();
    out.setTextColor(out.VgaTextColor.White, out.VgaTextColor.Red);
    out.clear();
    out.println("The Avery Kernel panicked!\n");
    out.printstr(isr.EXCEPTION_MESSAGES[r.int_no]);
    out.print("\n\n");
    out.println("The computer ran into a problem it could not recover from.\n");
    out.print("Error code: ");
    out.printHex(r.int_no);
    out.print("\n");
    if (r.int_no == 0x0E) {
        out.print("Key-code: ");
        out.printHex(r.err_code);
        out.print("\n");
    }
    out.print("\nIn 10 seconds, the kernel will a green screen with the register values.\n");
    out.print("If you do not understand what this means, please restart your computer.\n");
    out.print("If you do understand what this means, please report this to the developers.\n");

    // TODO: In production, change this to 200_000_0000, for debug purposes, we use 500_000_000
    delay(250_000_000);

    out.setTextColor(out.VgaTextColor.White, out.VgaTextColor.Green);
    out.clear();
    delay(10000);
    out.setCursorPos(0, 0);

    if (r.int_no == 0x0E) {
        // Page fault
        out.print("\n======== Page Fault Useful Information ========\n");
        out.print("Page fault error code: ");
        out.printHex(r.err_code);
        out.print("\n");
        out.print("Page fault at address: ");
        out.printHex(r.eip);
        out.print("\n");

        var cr2: u32 = undefined;
        asm volatile ("movl %%cr2, %[cr2]"
            : [cr2] "=r" (cr2),
        );

        out.print("CR2: ");
        out.printHex(cr2);
        out.print("\n");

        if ((r.err_code & 0x1) == 0) {
            out.print("* Page not present\n");
        } else {
            out.print("* Page present\n");
        }

        if ((r.err_code & 0x2) == 0) {
            out.print("* Read operation\n");
        } else {
            out.print("* Write operation\n");
        }

        if ((r.err_code & 0x4) == 0) {
            out.print("* User mode\n");
        } else {
            out.print("* Kernel mode\n");
        }
    } else {
        out.print("======= Register Values. Triggered by exception ");
        out.printHex(r.int_no);
        if (r.int_no == 0x0E) {
            out.print(" / ");
            out.printHex(r.err_code);
        }
        out.println(" =======\n");

        out.print("EIP: ");
        out.printHex(r.eip);
        out.print("\n");
        out.print("CS: ");
        out.printHex(r.cs);
        out.print("\n");
        out.print("EFLAGS: ");
        out.printHex(r.eflags);
        out.print("\n");
        out.print("ESP: ");
        out.printHex(r.esp);
        out.print("\n");
        out.print("SS: ");
        out.printHex(r.ss);
        out.print("\n");
        out.print("EDI: ");
        out.printHex(r.edi);
        out.print("\n");
        out.print("ESI: ");
        out.printHex(r.esi);
        out.print("\n");
        out.print("EBP: ");
        out.printHex(r.ebp);
        out.print("\n");
        out.print("EBX: ");
        out.printHex(r.ebx);
        out.print("\n");
        out.print("EDX: ");
        out.printHex(r.edx);
        out.print("\n");
        out.print("ECX: ");
        out.printHex(r.ecx);
        out.print("\n");
        out.print("EAX: ");
        out.printHex(r.eax);
        out.print("\n");
        out.print("GS: ");
        out.printHex(r.gs);
        out.print("\n");
        out.print("FS: ");
        out.printHex(r.fs);
        out.print("\n");
        out.print("ES: ");
        out.printHex(r.es);
        out.print("\n");
        out.print("DS: ");
        out.printHex(r.ds);
        out.print("\n");
        out.print("INT_NO: ");
        out.printHex(r.int_no);
        out.print("\n");
        out.print("ERR_CODE: ");
        out.printHex(r.err_code);
        out.print("\n");
        out.print("USERESP: ");
        out.printHex(r.useresp);
        out.print("\n");
    }

    while (true) {}
}
