const virtmem = @import("virtual_mem");
const physmem = @import("physical_mem");
const alloc = @import("allocator");
const mem = @import("memory");

pub const ProcessState = enum {
    Ready,
    Running,
    Blocked,
    Terminated,
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

    pub fn create(program_data: []const u8) ?*Process {
        @setRuntimeSafety(false);
        const process = alloc.store(Process);

        const new_pd_phys = physmem.allocPage() orelse return null;
        const new_pd: *[1024]u32 = @ptrFromInt(virtmem.physicalToVirtual(new_pd_phys) orelse return null);

        new_pd[0] = virtmem.page_directory[0];
        for (768..1024) |i| {
            new_pd[i] = virtmem.page_directory[i];
        }

        process.page_directory = new_pd_phys;
        process.state = .Ready;
        const old_pd = getCurrentPageDirectory();
        virtmem.loadPageDirectory(new_pd_phys);

        const program_pages = (program_data.len + physmem.PAGE_SIZE - 1) / physmem.PAGE_SIZE;
        const user_code = virtmem.allocUserPages(program_pages * physmem.PAGE_SIZE) orelse {
            virtmem.loadPageDirectory(old_pd);
            return null;
        };

        _ = memcpy(
            @as([*]u8, @ptrFromInt(user_code)),
            program_data.ptr,
            program_data.len,
        );

        process.entry_point = user_code;

        const user_stack_size = 4 * physmem.PAGE_SIZE;
        process.user_stack = virtmem.allocUserPages(user_stack_size) orelse {
            virtmem.loadPageDirectory(old_pd);
            return null;
        };

        process.kernel_stack = mem.getStackTop();
        process.stack_top = process.user_stack + user_stack_size - 1;

        virtmem.loadPageDirectory(old_pd);
        return process;
    }

    fn getCurrentPageDirectory() u32 {
        var cr3: u32 = undefined;
        asm volatile ("mov %%cr3, %[out]"
            : [out] "=r" (cr3),
        );
        return cr3;
    }

    pub fn switchTo(self: *const Process) void {
        virtmem.loadPageDirectory(self.page_directory);

        const USER_CODE_SELECTOR: u16 = 0x1B;
        const USER_DATA_SELECTOR: u16 = 0x23;

        switchToUserMode(self.entry_point, self.user_stack, USER_CODE_SELECTOR, USER_DATA_SELECTOR);
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
        \\mov %%esp, %%eax
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
        : [user_ds] "m" (user_data_segment),
          [user_ss] "m" (user_data_segment),
          [user_esp] "m" (user_stack),
          [user_cs] "m" (user_code_segment),
          [user_eip] "m" (entry_point),
        : "eax", "memory"
    );
}
