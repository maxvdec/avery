const virtmem = @import("virtual_mem");
const physmem = @import("physical_mem");
const alloc = @import("allocator");
const mem = @import("memory");
const out = @import("output");

pub const ProcessState = enum {
    Ready,
    Running,
    Blocked,
    Terminated,
};

pub const ProcessContext = struct {
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
    esi: u32,
    edi: u32,
    esp: u32,
    ebp: u32,
    eip: u32,
    eflags: u32,
    cr3: u32, // Page directory
};

extern fn memcpy(
    dest: [*]u8,
    src: [*]const u8,
    len: usize,
) [*]u8;

pub const Process = struct {
    pid: u32,
    page_directory: u32,
    user_stack: usize,
    kernel_stack: usize,
    state: ProcessState,
    stack_top: usize,
    entry_point: usize,
    context: ProcessContext,

    const STACK_SIZE = 0x2000; // 8KiB stack
    const USER_STACK_BASE = 0x7FFFE000;

    pub fn create(program_data: []const u8) ?*Process {
        @setRuntimeSafety(false);
        out.preserveMode();
        out.switchToSerial();

        const process = alloc.store(Process);
        process.pid = getNextPid();

        const pd_phys = physmem.allocPage() orelse {
            return null;
        };
        process.page_directory = pd_phys;

        const pd_virt = virtmem.mapPhysicalPage(pd_phys) orelse {
            physmem.freePage(pd_phys);
            return null;
        };

        const new_pd = @as(*[1024]u32, @ptrFromInt(pd_virt));

        for (new_pd) |*entry| entry.* = 0;

        const current_pd = virtmem.page_directory;

        if (current_pd[0] != 0) {
            new_pd[0] = current_pd[0];
        }

        var kernel_mappings_copied: u32 = 0;
        for (768..1024) |i| {
            new_pd[i] = current_pd[i];
            if (current_pd[i] != 0) {
                kernel_mappings_copied += 1;
            }
        }

        for (512..768) |i| {
            if (current_pd[i] != 0) {
                new_pd[i] = current_pd[i];
            }
        }

        const program_size = program_data.len;
        const program_pages = (program_size + 0xFFF) / 0x1000;
        const user_base = virtmem.USER_SPACE_START;

        out.print("Creating process: program_size=");
        out.printHex(program_size);
        out.print(", program_pages=");
        out.printn(program_pages);
        out.print(", user_base=");
        out.printHex(user_base);
        out.println("");

        var i: usize = 0;
        while (i < program_pages) : (i += 1) {
            const phys_page = physmem.allocPage() orelse {
                cleanup(process, i);
                return null;
            };

            const virt_addr = user_base + i * 4096;
            virtmem.mapPageInPD(virt_addr, phys_page, virtmem.PAGE_PRESENT | virtmem.PAGE_RW | virtmem.PAGE_USER, new_pd);

            out.print("Mapped program page ");
            out.printn(i);
            out.print(" at virt=");
            out.printHex(virt_addr);
            out.print(" to phys=");
            out.printHex(phys_page);
            out.println("");
        }

        var data_offset: usize = 0;
        i = 0;
        while (i < program_pages) : (i += 1) {
            const virt_addr = user_base + i * 4096;
            const phys_addr = virtmem.translateInPD(virt_addr, new_pd) orelse unreachable;

            const temp_virt = virtmem.mapPhysicalPage(phys_addr) orelse unreachable;

            const bytes_remaining = program_size - data_offset;
            const bytes_to_copy = if (bytes_remaining > 4096) 4096 else bytes_remaining;

            if (bytes_to_copy > 0) {
                out.print("Copying ");
                out.printn(bytes_to_copy);
                out.print(" bytes to temp_virt=");
                out.printHex(temp_virt);
                out.print(" (phys=");
                out.printHex(phys_addr);
                out.print(") from offset ");
                out.printn(data_offset);
                out.println("");

                _ = memcpy(@as([*]u8, @ptrFromInt(temp_virt)), program_data.ptr + data_offset, bytes_to_copy);
                data_offset += bytes_to_copy;

                const copied_data = @as([*]u8, @ptrFromInt(temp_virt));
                out.print("First 4 bytes copied: ");
                for (0..@min(4, bytes_to_copy)) |k| {
                    out.printHex(copied_data[k]);
                    out.print(" ");
                }
                out.println("");
            }

            if (bytes_to_copy < 4096) {
                const clear_ptr = @as([*]u8, @ptrFromInt(temp_virt + bytes_to_copy));
                for (0..(4096 - bytes_to_copy)) |j| {
                    clear_ptr[j] = 0;
                }
            }

            virtmem.unmapPhysicalPage(temp_virt);
        }

        const stack_pages = STACK_SIZE / 4096;
        const stack_bottom = USER_STACK_BASE - STACK_SIZE + 4096;

        out.print("Creating stack: USER_STACK_BASE=");
        out.printHex(USER_STACK_BASE);
        out.print(", STACK_SIZE=");
        out.printHex(STACK_SIZE);
        out.print(", stack_bottom=");
        out.printHex(stack_bottom);
        out.print(", stack_pages=");
        out.printn(stack_pages);
        out.println("");

        i = 0;
        while (i < stack_pages) : (i += 1) {
            const stack_page_addr = stack_bottom + i * 4096;
            const phys_page = physmem.allocPage() orelse {
                cleanup(process, program_pages + i);
                return null;
            };

            out.print("Mapping stack page ");
            out.printn(i);
            out.print(" at virt=");
            out.printHex(stack_page_addr);
            out.print(" to phys=");
            out.printHex(phys_page);
            out.println("");

            virtmem.mapPageInPD(stack_page_addr, phys_page, virtmem.PAGE_PRESENT | virtmem.PAGE_RW | virtmem.PAGE_USER, new_pd);

            const temp_stack_virt = virtmem.mapPhysicalPage(phys_page) orelse unreachable;
            const stack_ptr = @as([*]u8, @ptrFromInt(temp_stack_virt));
            for (0..4096) |j| {
                stack_ptr[j] = 0;
            }
            virtmem.unmapPhysicalPage(temp_stack_virt);
        }

        const kernel_stack_phys = physmem.allocPage() orelse {
            cleanup(process, program_pages + stack_pages);
            return null;
        };

        process.kernel_stack = virtmem.mapPhysicalPage(kernel_stack_phys) orelse {
            physmem.freePage(kernel_stack_phys);
            cleanup(process, program_pages + stack_pages);
            return null;
        };

        process.entry_point = user_base;
        process.user_stack = USER_STACK_BASE;
        process.stack_top = USER_STACK_BASE;
        process.state = ProcessState.Ready;

        process.context = ProcessContext{
            .eax = 0,
            .ebx = 0,
            .ecx = 0,
            .edx = 0,
            .esi = 0,
            .edi = 0,
            .esp = @intCast(process.user_stack),
            .ebp = @intCast(process.user_stack),
            .eip = @intCast(process.entry_point),
            .eflags = 0x202,
            .cr3 = pd_phys,
        };

        out.print("Verifying entry point mapping at ");
        out.printHex(process.entry_point);
        out.println("");

        const entry_check = virtmem.translateInPD(process.entry_point, new_pd);
        if (entry_check == null) {
            out.println("ERROR: Entry point is not mapped!");
        } else {
            out.print("Entry point mapped to physical: ");
            out.printHex(entry_check.?);
            out.println("");
        }

        out.print("Verifying stack mapping at ");
        out.printHex(process.user_stack);
        out.println("");

        const stack_check = virtmem.translateInPD(process.user_stack, new_pd);
        if (stack_check == null) {
            out.println("ERROR: Stack is not mapped!");
        } else {
            out.print("Stack mapped to physical: ");
            out.printHex(stack_check.?);
            out.println("");
        }

        virtmem.unmapPhysicalPage(pd_virt);
        out.restoreMode();
        return process;
    }

    pub fn switchTo(self: *Process) void {
        @setRuntimeSafety(false);

        if (self.state != ProcessState.Ready) {
            out.print("Warning: Switching to process in state other than Ready\n");
        }

        self.state = ProcessState.Running;

        const pd_virt = virtmem.mapPhysicalPage(self.page_directory) orelse unreachable;
        const new_pd = @as(*[1024]u32, @ptrFromInt(pd_virt));

        const entry_mapped = virtmem.translateInPD(self.entry_point, new_pd);
        const stack_mapped = virtmem.translateInPD(self.user_stack, new_pd);

        virtmem.unmapPhysicalPage(pd_virt);

        if (entry_mapped == null) {
            out.print("Error: Entry point not mapped in new page directory\n");
            return;
        }
        if (stack_mapped == null) {
            out.print("Error: User stack not mapped in new page directory\n");
            return;
        }

        out.print("Switching to process - Entry: ");
        out.printHex(self.entry_point);
        out.print(", Stack: ");
        out.printHex(self.user_stack);
        out.println("");

        virtmem.loadPageDirectory(self.page_directory);

        switchToUserMode(self.entry_point, self.user_stack, 0x23, 0x1B);
    }

    pub fn destroy(self: *Process) void {
        @setRuntimeSafety(false);

        self.state = ProcessState.Terminated;

        if (self.kernel_stack != 0) {
            const kernel_stack_phys = virtmem.translate(self.kernel_stack) orelse 0;
            if (kernel_stack_phys != 0) {
                physmem.freePage(kernel_stack_phys);
            }
        }

        if (self.page_directory != 0) {
            physmem.freePage(self.page_directory);
        }

        alloc.freeObject(Process, self);
    }

    pub fn saveContext(self: *Process, context: *const ProcessContext) void {
        self.context = context.*;
        self.state = ProcessState.Ready;
    }

    pub fn getContext(self: *const Process) *const ProcessContext {
        return &self.context;
    }

    fn cleanup(process: *Process, _: usize) void {
        @setRuntimeSafety(false);

        if (process.page_directory != 0) {
            physmem.freePage(process.page_directory);
        }

        alloc.freeObject(Process, process);
    }

    fn getCurrentPageDirectory() u32 {
        var cr3: u32 = undefined;
        asm volatile ("mov %%cr3, %[out]"
            : [out] "=r" (cr3),
        );
        return cr3;
    }
};

pub fn switchToUserMode(entry_point: u32, user_stack: u32, user_data_segment: u16, user_code_segment: u16) void {
    @setRuntimeSafety(false);

    out.preserveMode();
    out.switchToSerial();
    out.print("Final switch - Entry: ");
    out.printHex(entry_point);
    out.print(", Stack: ");
    out.printHex(user_stack);
    out.print(", DS: ");
    out.printHex(user_data_segment);
    out.print(", CS: ");
    out.printHex(user_code_segment);
    out.println("");
    out.restoreMode();

    // Ensure we have a valid stack pointer (subtract 4 to account for stack alignment)
    const aligned_stack = user_stack - 4;

    asm volatile (
        \\cli
        \\mov %[user_ds], %%ax
        \\mov %%ax, %%ds
        \\mov %%ax, %%es
        \\mov %%ax, %%fs
        \\mov %%ax, %%gs
        \\
        \\push %[user_ss]          # User SS
        \\push %[user_esp]         # User ESP
        \\pushf                    # EFLAGS
        \\pop %%eax
        \\or $0x200, %%eax        # Enable interrupts in user mode
        \\push %%eax              # Modified EFLAGS
        \\push %[user_cs]         # User CS
        \\push %[user_eip]        # User EIP
        \\iret                    # Switch to user mode
        :
        : [user_ds] "r" (user_data_segment),
          [user_ss] "r" (user_data_segment),
          [user_esp] "r" (aligned_stack),
          [user_cs] "r" (user_code_segment),
          [user_eip] "r" (entry_point),
        : "eax", "memory"
    );
}

var next_pid: u32 = 1;
pub fn getNextPid() u32 {
    @setRuntimeSafety(false);
    const pid = next_pid;
    next_pid += 1;
    return pid;
}
