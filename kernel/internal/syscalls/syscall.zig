const idt = @import("idt");

extern fn int80_handler() void;

pub fn initSyscall() void {
    idt.setGate(0x80, @as(u64, @intCast(@intFromPtr(&int80_handler))), KERNEL_CS, INTERRUPT_GATE_FLAGS);
}

const KERNEL_CS: u16 = 0x08;
const INTERRUPT_GATE_FLAGS: u8 = 0x8E;

pub fn perform(
    syscall_number: u32,
    arg1: u32,
    arg2: u32,
    arg3: u32,
    arg4: u32,
    arg5: u32,
) u32 {
    var ret: u32 = 0;
    asm volatile (
        \\movl %[num], %%eax
        \\movl %[a1], %%ebx
        \\movl %[a2], %%ecx
        \\movl %[a3], %%edx
        \\movl %[a4], %%esi
        \\movl %[a5], %%edi
        \\int $0x80
        \\movl %%eax, %[ret]
        : [ret] "=r" (ret),
        : [num] "rm" (syscall_number),
          [a1] "rm" (arg1),
          [a2] "rm" (arg2),
          [a3] "rm" (arg3),
          [a4] "rm" (arg4),
          [a5] "rm" (arg5),
        : "eax", "ebx", "ecx", "edx", "esi", "edi"
    );
    return ret;
}
