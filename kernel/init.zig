const str = @import("string");
const out = @import("output");
const gdt = @import("gdt");
const idt = @import("idt");
const sys = @import("system");
const isr = @import("isr");

fn causeGPF() void {
    asm volatile ("mov %%cr0, %%eax" ::: "eax");
}

pub export fn kernel_main() noreturn {
    // Init process
    gdt.initGdt();
    idt.initIdt();
    isr.initIsrs();
    asm volatile ("sti" ::: "memory");

    out.initOutputs();
    out.clear();

    out.println("The Avery Kernel");
    out.println("Created by Max Van den Eynde");
    out.println("Pre-Alpha Version: paph-0.01");

    while (true) {}
}
