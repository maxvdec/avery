const vmm = @import("virtual_mem");
const pmm = @import("physical_mem");
const out = @import("output");
const sys = @import("system");
const mem = @import("memory");
const alloc = @import("allocator");
const kalloc = @import("kern_allocator");
const ext = @import("extensions");
const sch = @import("scheduler");
const fusion = @import("fusion");
const ata = @import("ata");
const input = @import("input");

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

pub const ProcessContext = extern struct {
    eax: u32 = 0,
    ebx: u32 = 0,
    ecx: u32 = 0,
    edx: u32 = 0,
    esi: u32 = 0,
    edi: u32 = 0,
    ebp: u32 = 0,
    esp: u32 = 0,
    eip: u32 = 0,
    eflags: u32 = 0x202,
    cs: u32 = 0,
    ds: u32 = 0,
    es: u32 = 0,
    fs: u32 = 0,
    gs: u32 = 0,
    ss: u32 = 0,
    cr3: u32 = 0,
};

const USER_STACK_SIZE: usize = 2 * vmm.PAGE_SIZE;

const GDT_USER_CODE = 0x1B;
const GDT_USER_DATA = 0x23;

extern var kernel_extensions: u32;

extern fn switch_to_user_mode(
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
    esi: u32,
    edi: u32,
    ebp: u32,
    esp: u32,
    eip: u32,
    eflags: u32,
    cs: u32,
    ds: u32,
    es: u32,
    fs: u32,
    gs: u32,
    ss: u32,
    page_dir: u32,
) void;

pub extern fn switch_context(
    old_context: *ProcessContext,
    new_context: *ProcessContext,
) void;
pub extern fn get_context() ProcessContext;

pub var drive: *ata.AtaDrive = undefined;

pub const FileDescriptor = struct {
    fd: u32,
    mode: u32,
    flags: u32,
    path: []const u8,
};

pub const Process = struct {
    pid: u32,
    state: ProcessState,
    priority: sch.ProcessPriority,
    page_dir: vmm.PageDirectory,
    user_stack_base: usize,
    user_stack_size: usize,
    code_base: usize,
    code_size: usize,
    context: *ProcessContext,
    kernel_extensions: *ext.KernelExtensions = undefined,
    kernel_extensions_addr: u32 = 0,

    time_slice_start: u32 = 0,
    time_slice_remaining: u32 = 0,
    quantum_count: u32 = 0,
    total_cpu_time: u32 = 0,
    last_scheduled: u32 = 0,
    wait_time: u32 = 0,

    file_descriptors: mem.Array(FileDescriptor) = mem.Array(FileDescriptor).initKernel(),

    base_priority: sch.ProcessPriority = sch.ProcessPriority.Normal,
    priority_boost_time: u32 = 0,
    starvation_threshold: u32 = 1000,

    initialized: bool = false,
    input_state: ?*input.InputState = null,

    fn setupStack(self: *Process) u32 {
        @setRuntimeSafety(false);
        const stack_pages = USER_STACK_SIZE / vmm.PAGE_SIZE;
        const stack_base_paddr = pmm.allocPages(stack_pages) orelse {
            out.print("Failed to allocate user stack for process ");
            out.printn(self.pid);
            out.println("");
            return 0;
        };

        for (0..stack_pages) |i| {
            const virt_addr = vmm.USER_STACK_VADDR - USER_STACK_SIZE + (i * vmm.PAGE_SIZE);
            const phys_addr = stack_base_paddr + (i * vmm.PAGE_SIZE);

            vmm.mapUserPage(self.page_dir, virt_addr, phys_addr, vmm.PAGE_PRESENT | vmm.PAGE_RW | vmm.PAGE_USER);
        }
        self.user_stack_base = vmm.USER_STACK_VADDR - USER_STACK_SIZE;
        self.user_stack_size = USER_STACK_SIZE;

        return vmm.USER_STACK_VADDR;
    }

    pub fn createProcess(code: []const u8, loadAt: usize, priority: sch.ProcessPriority) ?*Process {
        @setRuntimeSafety(false);
        var proc = kalloc.storeKernel(Process);

        proc.pid = next_pid;
        next_pid += 1;
        proc.state = ProcessState.Ready;
        proc.priority = priority;
        proc.base_priority = priority;
        proc.code_size = code.len;

        const current_time = sys.getTimerTicks();
        proc.time_slice_remaining = priority.getTimeSlice();
        proc.last_scheduled = current_time;
        proc.quantum_count = 0;

        proc.page_dir = vmm.createUserPageDirectory() orelse {
            out.print("Failed to create page directory for process ");
            out.printn(proc.pid);
            out.println("");
            return null;
        };

        const code_pages = (code.len + vmm.PAGE_SIZE - 1) / vmm.PAGE_SIZE;
        const code_paddr = pmm.allocPages(code_pages) orelse {
            out.print("Failed to allocate code pages for process ");
            out.printn(proc.pid);
            out.println("");
            return null;
        };

        const code_vaddr = vmm.tempMap(code_paddr, code_pages);

        _ = memcpy(@ptrFromInt(code_vaddr), code.ptr, code.len);

        const real_addr = if (loadAt != 0) loadAt else vmm.USER_CODE_VADDR;

        for (0..code_pages) |i| {
            const vaddr = real_addr + (i * vmm.PAGE_SIZE);
            const paddr = code_paddr + (i * vmm.PAGE_SIZE);

            vmm.mapUserPage(proc.page_dir, vaddr, paddr, vmm.PAGE_PRESENT | vmm.PAGE_RW | vmm.PAGE_USER);
        }

        proc.code_base = real_addr;

        const stack_top = proc.setupStack();

        proc.context = kalloc.storeKernel(ProcessContext);
        proc.context.* = ProcessContext{};

        proc.context.eip = proc.code_base;
        proc.context.esp = stack_top;
        proc.context.eflags = 0x202; // Set IF (Interrupt Flag) to enable interrupts

        proc.context.cs = GDT_USER_CODE;
        proc.context.ds = GDT_USER_DATA;
        proc.context.es = GDT_USER_DATA;
        proc.context.fs = GDT_USER_DATA;
        proc.context.gs = GDT_USER_DATA;
        proc.context.ss = GDT_USER_DATA;

        var kernel_ext = kalloc.storeKernel(ext.KernelExtensions);
        kernel_ext.* = .{};
        kernel_ext.requestTerminal();
        kernel_ext.addProcess(proc);
        kernel_ext.setScheduler(sch.scheduler.?);
        drive = kalloc.storeKernel(ata.AtaDrive);
        drive.* = fusion.getAtaController().master;
        kernel_ext.setAtaDrive(drive);

        proc.kernel_extensions = kernel_ext;
        proc.kernel_extensions_addr = @intFromPtr(kernel_ext);

        process_list.append(proc);

        vmm.tempUnmap(code_vaddr);

        sch.scheduler.?.addProcess(proc);

        return proc;
    }

    pub fn run(self: *Process) void {
        @setRuntimeSafety(false);
        out.preserveMode();
        out.switchToSerial();
        out.print("RUNNING PROCESS ");
        out.printn(self.pid);
        out.println("");
        out.restoreMode();
        current_process = self;
        self.state = ProcessState.Running;

        const current_time = sys.getTimerTicks();
        self.time_slice_start = current_time;
        self.last_scheduled = current_time;

        if (!self.initialized) {
            out.switchToSerial();
            out.print("Page dir physical: ");
            out.printHex(self.page_dir.physical);
            out.print("\n");
            out.print("Kernel extensions address: ");
            out.printHex(self.kernel_extensions_addr);
            out.print("\n");

            self.kernel_extensions.updateKernelAlloc();

            kernel_extensions = self.kernel_extensions_addr;

            sch.current_process = self;
            self.initialized = true;

            switch_to_user_mode(
                self.context.eax,
                self.context.ebx,
                self.context.ecx,
                self.context.edx,
                self.context.esi,
                self.context.edi,
                self.context.ebp,
                self.context.esp,
                self.context.eip,
                self.context.eflags,
                self.context.cs,
                self.context.ds,
                self.context.es,
                self.context.fs,
                self.context.gs,
                self.context.ss,
                self.page_dir.physical,
            );
        } else {
            out.switchToSerial();
            out.print("Resuming process ");
            out.printn(self.pid);
            out.println("");

            self.kernel_extensions.updateKernelAlloc();

            kernel_extensions = self.kernel_extensions_addr;

            self.initialized = true;

            const old = sch.current_process.?.context;

            switch_context(old, self.context);
        }
    }

    pub fn suspendProcess(self: *Process) void {
        @setRuntimeSafety(false);
        if (self.state == .Running) {
            self.state = .Ready;

            const current_time = sys.getTimerTicks();
            const time_used = current_time - self.time_slice_start;
            self.total_cpu_time += time_used;

            if (self.time_slice_remaining > time_used) {
                self.time_slice_remaining -= time_used;
            } else {
                self.time_slice_remaining = 0;
            }

            self.last_scheduled = current_time;
        }
    }

    pub fn block(self: *Process) void {
        @setRuntimeSafety(false);
        self.state = ProcessState.Blocked;
        self.suspendProcess();
    }

    pub fn unblock(self: *Process) void {
        @setRuntimeSafety(false);
        if (self.state == .Blocked) {
            self.state = .Ready;
            self.time_slice_remaining = self.priority.getTimeSlice();
            self.quantum_count = 0;
        }
    }

    pub fn terminate(self: *Process) void {
        @setRuntimeSafety(false);

        self.state = ProcessState.Terminated;
        sch.scheduler.?.removeProcess(self);
        self.cleanup();

        if (current_process != null and current_process.?.pid == self.pid) {
            current_process = null;
            sch.scheduler.?.schedule();
        }
    }

    pub fn cleanup(self: *Process) void {
        @setRuntimeSafety(false);

        if (self.page_dir.physical != 0) {
            vmm.destroyPageDirectory(self.page_dir);
        }

        kalloc.freeKernelObject(ext.KernelExtensions, self.kernel_extensions);

        if (self.code_base != 0) {
            const code_pages = (self.code_size + vmm.PAGE_SIZE - 1) / vmm.PAGE_SIZE;
            const code_paddr = vmm.tempMap(self.code_base, code_pages);
            pmm.freePages(code_paddr, code_pages);
            vmm.tempUnmap(self.code_base);
        }
    }

    pub fn updatePriority(self: *Process) void {
        @setRuntimeSafety(false);
        const current_time = sys.getTimerTicks();

        if (self.state == ProcessState.Ready and
            current_time - self.last_scheduled > self.starvation_threshold)
        {
            if (@intFromEnum(self.priority) > @intFromEnum(sch.ProcessPriority.Critical)) {
                self.priority = @enumFromInt(@intFromEnum(self.priority) - 1);
                self.priority_boost_time = current_time;
            }
        }

        if (self.priority_boost_time > 0 and
            current_time - self.priority_boost_time > 500)
        {
            if (@intFromEnum(self.priority) < @intFromEnum(self.base_priority)) {
                self.priority = @enumFromInt(@intFromEnum(self.priority) + 1);
                if (self.priority == self.base_priority) {
                    self.priority_boost_time = 0;
                }
            }
        }
    }

    pub fn createIdleProcess() void {
        @setRuntimeSafety(false);
        const program: []const u8 = &[_]u8{
            0xEB, 0xFE, // jmp $
        };

        var process = Process.createProcess(program, 0, .Idle);
        process.?.pid = 0;
        process.?.state = .Ready;
        next_pid = 1;
    }

    pub fn debugProcessContext(ctx: *ProcessContext) void {
        out.print("ProcessContext Size: ");
        out.printn(@sizeOf(ProcessContext));
        out.println("");

        const fields = [_]struct {
            name: []const u8,
            value: u32,
            offset: usize,
        }{
            .{ .name = "EAX", .value = ctx.eax, .offset = @offsetOf(ProcessContext, "eax") },
            .{ .name = "EBX", .value = ctx.ebx, .offset = @offsetOf(ProcessContext, "ebx") },
            .{ .name = "ECX", .value = ctx.ecx, .offset = @offsetOf(ProcessContext, "ecx") },
            .{ .name = "EDX", .value = ctx.edx, .offset = @offsetOf(ProcessContext, "edx") },
            .{ .name = "ESI", .value = ctx.esi, .offset = @offsetOf(ProcessContext, "esi") },
            .{ .name = "EDI", .value = ctx.edi, .offset = @offsetOf(ProcessContext, "edi") },
            .{ .name = "EBP", .value = ctx.ebp, .offset = @offsetOf(ProcessContext, "ebp") },
            .{ .name = "ESP", .value = ctx.esp, .offset = @offsetOf(ProcessContext, "esp") },
            .{ .name = "EIP", .value = ctx.eip, .offset = @offsetOf(ProcessContext, "eip") },
            .{ .name = "EFLAGS", .value = ctx.eflags, .offset = @offsetOf(ProcessContext, "eflags") },
            .{ .name = "CS", .value = ctx.cs, .offset = @offsetOf(ProcessContext, "cs") },
            .{ .name = "DS", .value = ctx.ds, .offset = @offsetOf(ProcessContext, "ds") },
            .{ .name = "ES", .value = ctx.es, .offset = @offsetOf(ProcessContext, "es") },
            .{ .name = "FS", .value = ctx.fs, .offset = @offsetOf(ProcessContext, "fs") },
            .{ .name = "GS", .value = ctx.gs, .offset = @offsetOf(ProcessContext, "gs") },
            .{ .name = "SS", .value = ctx.ss, .offset = @offsetOf(ProcessContext, "ss") },
        };

        for (fields) |field| {
            out.print(field.name);
            out.print(": ");
            out.printHex(field.value);
            out.print(", Offset: ");
            out.printHex(field.offset);
            out.println("");
        }
    }
};

pub fn beginAll() void {
    sch.scheduleNext();
}

var current_process: ?*Process = null;
var process_list: mem.Array(*Process) = .init();
var next_pid: u32 = 1;

pub fn processTest() void {
    @setRuntimeSafety(false);

    const bytes = [_]u8{
        0xEB, 0xFE, // Infinite loop: jmp to the same instruction
    };

    const proc = Process.createProcess(&bytes, 0, .Normal) orelse {
        out.println("Failed to create process.");
        return;
    };

    proc.run();
}

pub fn createFallbackProcess() ?*Process {
    @setRuntimeSafety(false);

    const bytes = [_]u8{
        0xEB, 0xFE, // Infinite loop: jmp to the same instruction
    };

    return Process.createProcess(&bytes, 0, .Normal);
}
