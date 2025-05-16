const str = @import("string");
const out = @import("output");
const gdt = @import("gdt");
const idt = @import("idt");
const sys = @import("system");
const isr = @import("isr");
const irq = @import("irq");
const time = @import("time");
const keyboard = @import("keyboard");
const in = @import("input");

pub fn causeGPF() void {
    @setRuntimeSafety(false);
    asm volatile (
        \\ xor %bx, %bx
        \\ div %bx
    );
}

export fn kernel_main() noreturn {
    out.initOutputs();
    gdt.init();
    idt.init();
    isr.init();
    asm volatile ("sti");
    irq.init();

    out.setTextColor(out.VgaTextColor.LightGray, out.VgaTextColor.Black);
    //out.clear();
    out.println("The Avery Kernel");
    out.println("Created by Max Van den Eynde");
    out.println("Pre-Alpha Version: paph-0.01");
    const mystr = in.readln();
    out.print("You entered: ");
    out.printstr(mystr);
    out.print("\n");

    while (true) {
        asm volatile ("hlt");
    }
}
