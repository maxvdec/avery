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

    const STACK_SIZE = 0x2000; // 8 KiB stack
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
        for (768..1024) |i| {
            new_pd[i] = current_pd[i]; // Copy kernel mappings
        }

        const program_size = program_data.len;
        const program_pages = (program_size + 0xFFF) / 0x1000;

        const user_base = virtmem.USER_SPACE_START;

        var i: usize = 0;
        while (i < program_pages) : (i += 1) {
            const phys_page = physmem.allocPage() orelse {
                // Cleanup on failure
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

        // Clean up temporary mapping
        virtmem.freeVirtual(temp_mapping, program_size);

        // Allocate user stack
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

        // Allocate kernel stack
        const kernel_stack_phys = physmem.allocPage() orelse {
            cleanup(process, program_pages + stack_pages);
            return null;
        };

        process.kernel_stack = virtmem.mapPhysicalPage(kernel_stack_phys) orelse {
            physmem.freePage(kernel_stack_phys);
            cleanup(process, program_pages + stack_pages);
            return null;
        };

        // Initialize process fields
        process.entry_point = user_base;
        process.user_stack = USER_STACK_BASE;
        process.stack_top = USER_STACK_BASE;
        process.state = ProcessState.Ready;

        // Initialize context for first run
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
            .eflags = 0x202, // Interrupts enabled, reserved bit set
            .cr3 = @intCast(process.page_directory),
        };

        // Unmap the temporary page directory mapping
        virtmem.unmapPhysicalPage(pd_virt);

        return process;
    }

    pub fn switchTo(self: *Process) void {
        @setRuntimeSafety(false);

        if (self.state != ProcessState.Ready) {
            out.print("Warning: Switching to process in state other than Ready\n");
        }

        self.state = ProcessState.Running;

        // Load the process page directory
        virtmem.loadPageDirectory(self.page_directory);

        // Switch to user mode with the process context
        switchToUserMode(@intCast(self.entry_point), @intCast(self.user_stack), 0x23, // User data segment (GDT selector)
            0x1B // User code segment (GDT selector)
        );
    }

    pub fn destroy(self: *Process) void {
        @setRuntimeSafety(false);

        self.state = ProcessState.Terminated;

        // TODO: Free all allocated pages for this process
        // This would involve walking through the page directory and freeing all user pages

        // Free kernel stack
        if (self.kernel_stack != 0) {
            const kernel_stack_phys = virtmem.translate(self.kernel_stack) orelse 0;
            if (kernel_stack_phys != 0) {
                physmem.freePage(kernel_stack_phys);
            }
        }

        // Free page directory
        if (self.page_directory != 0) {
            physmem.freePage(self.page_directory);
        }

        // Free process structure
        alloc.free(@intFromPtr(self), @sizeOf(Process));
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
            // Free allocated pages (this is simplified - in reality we'd walk the page tables)
            var i: usize = 0;
            while (i < pages_allocated) : (i += 1) {
                // This is a simplified cleanup - real implementation would walk page tables
                const phys = physmem.allocPage() orelse continue;
                physmem.freePage(phys);
            }

            physmem.freePage(process.page_directory);
        }

        alloc.free(@intFromPtr(process), @sizeOf(Process));
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
