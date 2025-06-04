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

    const STACK_SIZE = 0x2000; // 8Kib stack
    const USER_STACK_BASE = 0x7FFFF000;

    pub fn create(program_data: []const u8) ?*Process {
        @setRuntimeSafety(false);

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

        var i: usize = 0;
        while (i < program_pages) : (i += 1) {
            const phys_page = physmem.allocPage() orelse {
                cleanup(process, i);
                return null;
            };
            virtmem.mapPageInPD(user_base + i * 4096, phys_page, virtmem.PAGE_PRESENT | virtmem.PAGE_RW | virtmem.PAGE_USER, new_pd);
        }

        const temp_mapping = virtmem.allocVirtual(program_size, virtmem.PAGE_PRESENT | virtmem.PAGE_RW) orelse {
            cleanup(process, program_pages);
            return null;
        };

        i = 0;
        while (i < program_pages) : (i += 1) {
            const phys = virtmem.translate(user_base + i * 4096) orelse unreachable;
            virtmem.mapPage(temp_mapping + i * 4096, phys, virtmem.PAGE_PRESENT | virtmem.PAGE_RW);
        }

        _ = memcpy(@as([*]u8, @ptrFromInt(temp_mapping)), program_data.ptr, program_data.len);
        virtmem.freeVirtual(temp_mapping, program_size);

        const stack_pages = STACK_SIZE / 4096;
        const stack_base = USER_STACK_BASE - STACK_SIZE;

        i = 0;
        while (i < stack_pages) : (i += 1) {
            const phys_page = physmem.allocPage() orelse {
                cleanup(process, program_pages + i);
                return null;
            };
            virtmem.mapPageInPD(stack_base + i * 4096, phys_page, virtmem.PAGE_PRESENT | virtmem.PAGE_RW | virtmem.PAGE_USER, new_pd);
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

        virtmem.unmapPhysicalPage(pd_virt);
        return process;
    }

    pub fn switchTo(self: *Process) void {
        @setRuntimeSafety(false);

        if (self.state != ProcessState.Ready) {
            out.print("Warning: Switching to process in state other than Ready\n");
        }

        self.state = ProcessState.Running;
        const entry_point = self.entry_point;
        const user_stack = self.user_stack;

        virtmem.loadPageDirectory(self.page_directory);

        switchToUserMode(entry_point, user_stack, 0x23, // User data segment (GDT selector)
            0x1B);
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

    fn cleanup(process: *Process, pages_allocated: usize) void {
        @setRuntimeSafety(false);

        if (process.page_directory != 0) {
            var i: usize = 0;
            while (i < pages_allocated) : (i += 1) {
                const phys = physmem.allocPage() orelse continue;
                physmem.freePage(phys);
            }

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
    // We're running some tests before switching to user mode
    const mapped_stack = virtmem.translate(user_stack) orelse 0;
    const mapped_entry = virtmem.translate(entry_point) orelse 0;

    if (mapped_entry == 0) {
        out.print("Error: Entry point not mapped in user space\n");
    } else {
        out.print("Entry point mapped at: ");
        out.printHex(mapped_entry);
        out.println("");
    }

    if (mapped_stack == 0) {
        out.print("Error: User stack not mapped in user space\n");
    } else {
        out.print("User stack mapped at: ");
        out.printHex(mapped_stack);
        out.println("");
    }

    out.print("Entry Point: ");
    out.printHex(entry_point);
    out.println("");
    out.println("User Stack: ");
    out.printHex(user_stack);
    out.println("");
    out.println("User Data Segment: ");
    out.printHex(user_data_segment);
    out.println("");
    out.println("User Code Segment: ");
    out.printHex(user_code_segment);
    out.println("");
    out.restoreMode();

    asm volatile (
        \\cli
        \\mov %[user_ds], %%ax
        \\mov %%ax, %%ds
        \\mov %%ax, %%es
        \\mov %%ax, %%fs
        \\mov %%ax, %%gs
        \\
        \\push %[user_ss]          // User SS
        \\push %[user_esp]         // User ESP
        \\pushf                    // EFLAGS
        \\pop %%eax
        \\or $0x200, %%eax        // Enable interrupts in user mode
        \\push %%eax              // Modified EFLAGS
        \\push %[user_cs]         // User CS
        \\push %[user_eip]        // User EIP
        \\iret                    // Switch to user mode
        :
        : [user_ds] "r" (user_data_segment),
          [user_ss] "r" (user_data_segment),
          [user_esp] "r" (user_stack),
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
