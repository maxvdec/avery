const vmm = @import("virtual_mem");
const pmm = @import("physical_mem");
const out = @import("output");
const sys = @import("system");
const mem = @import("memory");
const alloc = @import("allocator");

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

pub const ProcessContext = packed struct {
    eax: u32 = 0,
    ebx: u32 = 0,
    ecx: u32 = 0,
    edx: u32 = 0,
    esi: u32 = 0,
    edi: u32 = 0,
    ebp: u32 = 0,
    esp: u32 = 0,
    eip: u32 = 0,
    eflags: u32 = 0,
    cs: u32 = 0,
    ds: u32 = 0,
    es: u32 = 0,
    fs: u32 = 0,
    gs: u32 = 0,
    ss: u32 = 0,
};

const USER_STACK_SIZE: usize = 2 * vmm.PAGE_SIZE;

const GDT_USER_CODE = 0x1B;
const GDT_USER_DATA = 0x23;

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

pub const Process = struct {
    pid: u32,
    state: ProcessState,
    page_dir: vmm.PageDirectory,
    user_stack_base: usize,
    user_stack_size: usize,
    code_base: usize,
    code_size: usize,
    context: ProcessContext,

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

    pub fn create_process(code: []const u8) ?*Process {
        @setRuntimeSafety(false);
        var proc = alloc.store(Process);

        proc.pid = next_pid;
        next_pid += 1;
        proc.state = ProcessState.Ready;
        proc.code_size = code.len;

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

        const code_vaddr = vmm.tempMap(code_paddr);

        _ = memcpy(@ptrFromInt(code_vaddr), code.ptr, code.len);

        for (0..code_pages) |i| {
            const vaddr = vmm.USER_CODE_VADDR + (i * vmm.PAGE_SIZE);
            const paddr = code_paddr + (i * vmm.PAGE_SIZE);

            vmm.mapUserPage(proc.page_dir, vaddr, paddr, vmm.PAGE_PRESENT | vmm.PAGE_RW | vmm.PAGE_USER);
        }

        proc.code_base = vmm.USER_CODE_VADDR;

        const stack_top = proc.setupStack();

        proc.context = ProcessContext{};

        proc.context.eip = vmm.USER_CODE_VADDR;
        proc.context.esp = stack_top;
        proc.context.eflags = 0x202; // Set IF (Interrupt Flag) to enable interrupts

        proc.context.cs = GDT_USER_CODE;
        proc.context.ds = GDT_USER_DATA;
        proc.context.es = GDT_USER_DATA;
        proc.context.fs = GDT_USER_DATA;
        proc.context.gs = GDT_USER_DATA;
        proc.context.ss = GDT_USER_DATA;

        process_list.append(proc);

        vmm.tempUnmap(code_vaddr);
        return proc;
    }

    pub fn run(self: *Process) void {
        @setRuntimeSafety(false);
        current_process = self;
        self.state = ProcessState.Running;

        out.switchToSerial();
        out.print("Page dir physical: ");
        out.printHex(self.page_dir.physical);
        out.print("\n");

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

var current_process: ?*Process = null;
var process_list: mem.Array(*Process) = .init();
var next_pid: u32 = 1;

pub fn processTest() void {
    @setRuntimeSafety(false);

    const bytes = [_]u8{
        0xEB, 0xFE, // Infinite loop: jmp to the same instruction
    };

    const proc = Process.create_process(&bytes) orelse {
        out.println("Failed to create process.");
        return;
    };

    proc.run();
}
