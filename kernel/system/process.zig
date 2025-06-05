const vmm = @import("virtual_mem");
const pmm = @import("physical_mem");
const out = @import("output");
const sys = @import("system");
const mem = @import("memory");
const alloc = @import("allocator");

pub const ProcessState = enum { Running, Stopped, Waiting, Ready, Terminated };

pub const ProcessCPU = struct {
    esp: usize,
    eip: usize,
    ebp: usize,
    eax: usize,
    ebx: usize,
    ecx: usize,
    edx: usize,
    esi: usize,
    edi: usize,
    cs: u16,
    ds: u16,
    es: u16,
    fs: u16,
    gs: u16,
    ss: u32,
    eflags: u32,

    pub fn init() ProcessCPU {
        return ProcessCPU{
            .esp = 0,
            .eip = 0,
            .ebp = 0,
            .eax = 0,
            .ebx = 0,
            .ecx = 0,
            .edx = 0,
            .esi = 0,
            .edi = 0,
            .cs = 0x08, // User code segment
            .ds = 0x10, // User data segment
            .es = 0x10,
            .fs = 0x10,
            .gs = 0x10,
            .ss = 0x10, // User stack segment
            .eflags = 0x202, // Interrupts enabled
        };
    }
};

const USER_STACK_SIZE = 0x10000; // 64 KiB
const KERNEL_STACK_SIZE = 0x4000; // 16 KiB
const USER_STACK_TOP = 0x7FFF_FFFF; // Top of user stack (4 GiB - 1)
const USER_CODE_BASE = 0x400000; // 4 MiB - standard user code base

// Process table management
const MAX_PROCESSES = 256;
var process_table: [MAX_PROCESSES]?*Process = [_]?*Process{null} ** MAX_PROCESSES;
var next_pid: u32 = 1;
var current_process: ?*Process = null;

extern fn memset(
    dest: [*]u8,
    value: u8,
    len: usize,
) [*]u8;

pub const Process = struct {
    id: u32,
    name: []const u8,
    state: ProcessState,
    page_dir: vmm.PageDirectory = undefined,
    cpu: ProcessCPU = undefined,
    kernel_stack: u32 = 0,
    user_stack: u32 = 0,
    code_base: u32 = 0,
    code_size: u32 = 0,
    data_base: u32 = 0,
    data_size: u32 = 0,
    parent_id: u32 = 0,

    pub fn init(id: u32, name: []const u8) Process {
        return Process{
            .id = id,
            .name = name,
            .state = ProcessState.Ready,
            .cpu = ProcessCPU.init(),
        };
    }

    pub fn setupMemory(self: *Process) bool {
        @setRuntimeSafety(false);

        const pd_phys = pmm.allocPage() orelse {
            out.print("Failed to allocate page directory for process ");
            out.printn(self.id);
            out.println("");
            return false;
        };

        // Initialize page directory
        self.page_dir = vmm.initPageDirectory(pd_phys) orelse {
            pmm.freePage(pd_phys);
            out.print("Failed to initialize page directory for process ");
            out.printn(self.id);
            out.println("");
            return false;
        };
        // Switch to process page directory temporarily
        const old_pd = vmm.page_directory;
        vmm.loadPageDirectory(self.page_dir.virtual);

        // Map kernel space (higher half)
        if (!self.mapKernelSpace()) {
            vmm.page_directory = old_pd;
            pmm.freePage(pd_phys);
            return false;
        }

        // Allocate kernel stack
        self.kernel_stack = vmm.allocVirtual(KERNEL_STACK_SIZE, vmm.PAGE_PRESENT | vmm.PAGE_RW) orelse {
            vmm.page_directory = old_pd;
            pmm.freePage(pd_phys);
            out.print("Failed to allocate kernel stack for process ");
            out.printn(self.id);
            out.println("");
            return false;
        };

        // Allocate user stack
        self.user_stack = vmm.allocUserPages(USER_STACK_SIZE) orelse {
            vmm.freeVirtual(self.kernel_stack, KERNEL_STACK_SIZE);
            vmm.page_directory = old_pd;
            pmm.freePage(pd_phys);
            out.print("Failed to allocate user stack for process ");
            out.printn(self.id);
            out.println("");
            return false;
        };

        // Set up CPU state
        self.cpu.esp = USER_STACK_TOP - 4; // Leave some space at top
        self.cpu.ebp = USER_STACK_TOP - 4;

        // Restore original page directory
        vmm.page_directory = old_pd;
        return true;
    }

    fn mapKernelSpace(_: *Process) bool {
        // Map the first 4MB of physical memory to kernel space
        // This ensures kernel code and data are accessible
        var addr: usize = 0;
        while (addr < 0x400000) : (addr += vmm.PAGE_SIZE) {
            vmm.mapPage(vmm.KERNEL_MEM_BASE + addr, addr, vmm.PAGE_PRESENT | vmm.PAGE_RW);
        }
        return true;
    }

    pub fn loadProgram(self: *Process, code: []const u8) bool {
        @setRuntimeSafety(false);

        if (code.len == 0) {
            out.print("Empty program code for process ");
            out.printn(self.id);
            out.println("");
            return false;
        }

        // Calculate pages needed for code
        const pages_needed = (code.len + vmm.PAGE_SIZE - 1) / vmm.PAGE_SIZE;
        self.code_size = @intCast(code.len);

        // Switch to process page directory
        const old_pd = vmm.page_directory;
        vmm.loadPageDirectory(self.page_dir.physical);

        // Allocate virtual memory for code
        self.code_base = vmm.allocUserPages(pages_needed * vmm.PAGE_SIZE) orelse {
            vmm.page_directory = old_pd;
            out.print("Failed to allocate code memory for process ");
            out.printn(self.id);
            out.println("");
            return false;
        };

        // Copy code to allocated memory
        const code_ptr = @as([*]u8, @ptrFromInt(self.code_base));
        for (code, 0..) |byte, i| {
            code_ptr[i] = byte;
        }

        // Set entry point
        self.cpu.eip = self.code_base;

        // Restore original page directory
        vmm.page_directory = old_pd;

        out.print("Loaded program for process ");
        out.printn(self.id);
        out.print(" at 0x");
        out.printHex(self.code_base);
        out.println("");
        return true;
    }

    pub fn cleanup(self: *Process) void {
        @setRuntimeSafety(false);

        // Switch to process page directory to clean up
        const old_pd = vmm.page_directory;
        vmm.loadPageDirectory(self.page_dir.physical);

        // Free user stack
        if (self.user_stack != 0) {
            vmm.freeUserPages(self.user_stack, USER_STACK_SIZE);
        }

        // Free code memory
        if (self.code_base != 0) {
            const pages_needed = (self.code_size + vmm.PAGE_SIZE - 1) / vmm.PAGE_SIZE;
            vmm.freeUserPages(self.code_base, pages_needed * vmm.PAGE_SIZE);
        }

        // Free data memory if allocated
        if (self.data_base != 0) {
            const pages_needed = (self.data_size + vmm.PAGE_SIZE - 1) / vmm.PAGE_SIZE;
            vmm.freeUserPages(self.data_base, pages_needed * vmm.PAGE_SIZE);
        }

        // Restore original page directory
        vmm.page_directory = old_pd;

        // Free kernel stack
        if (self.kernel_stack != 0) {
            vmm.freeVirtual(self.kernel_stack, KERNEL_STACK_SIZE);
        }

        // Free page directory
        pmm.freePage(self.page_dir.physical);

        self.state = ProcessState.Terminated;
    }

    pub fn program(self: *Process, code: []const u8) void {
        if (!self.setupMemory()) {
            out.print("Failed to setup memory for process ");
            out.printn(self.id);
            out.println("");
            self.state = ProcessState.Terminated;
            return;
        }

        if (!self.loadProgram(code)) {
            out.print("Failed to load program for process ");
            out.printn(self.id);
            out.println("");
            self.cleanup();
            return;
        }

        self.state = ProcessState.Ready;
        out.print("Process ");
        out.printn(self.id);
        out.print(" '");
        out.print(self.name);
        out.println("' ready to run");
    }
};

// Process management functions
pub fn createProcess(name: []const u8) ?*Process {
    @setRuntimeSafety(false);

    // Find free slot in process table
    var slot_index: usize = 0;
    while (slot_index < MAX_PROCESSES) : (slot_index += 1) {
        if (process_table[slot_index] == null) break;
    } else {
        out.println("Process table full!");
        return null;
    }

    // Allocate memory for process
    const process_ptr = alloc.store(Process);

    // Initialize process
    process_ptr.* = Process.init(next_pid, name);
    process_table[slot_index] = process_ptr;
    next_pid += 1;

    out.print("Created process ");
    out.printn(process_ptr.id);
    out.print(" '");
    out.print(name);
    out.println("'");
    return process_ptr;
}

pub fn destroyProcess(process: *Process) void {
    @setRuntimeSafety(false);

    // Find process in table
    for (process_table, 0..) |proc, i| {
        if (proc) |p| {
            if (p.id == process.id) {
                // Clean up process resources
                process.cleanup();

                // Remove from table
                process_table[i] = null;

                // Free process memory
                alloc.free(process);

                out.print("Destroyed process ");
                out.printn(process.id);
                out.println("");
                return;
            }
        }
    }
}

pub fn findProcess(pid: u32) ?*Process {
    for (process_table) |proc| {
        if (proc) |p| {
            if (p.id == pid) return p;
        }
    }
    return null;
}

pub fn scheduleNext() ?*Process {
    // Simple round-robin scheduler
    var start_index: usize = 0;

    // Find current process index
    if (current_process) |curr| {
        for (process_table, 0..) |proc, i| {
            if (proc) |p| {
                if (p.id == curr.id) {
                    start_index = (i + 1) % MAX_PROCESSES;
                    break;
                }
            }
        }
    }

    // Find next ready process
    var index = start_index;
    var count: usize = 0;
    while (count < MAX_PROCESSES) : (count += 1) {
        if (process_table[index]) |proc| {
            if (proc.state == ProcessState.Ready) {
                return proc;
            }
        }
        index = (index + 1) % MAX_PROCESSES;
    }

    return null;
}

pub fn switchProcess(new_process: *Process) void {
    @setRuntimeSafety(false);

    // Save current process state if any
    if (current_process) |curr| {
        if (curr.state == ProcessState.Running) {
            curr.state = ProcessState.Ready;
        }
        // CPU state would be saved by interrupt handler
    }

    // Switch to new process
    current_process = new_process;
    new_process.state = ProcessState.Running;

    // Load new page directory
    vmm.loadPageDirectory(new_process.page_dir.physical);

    out.print("Switched to process ");
    out.printn(new_process.id);
    out.print(" '");
    out.print(new_process.name);
    out.println("'");
}

pub fn getCurrentProcess() ?*Process {
    return current_process;
}

pub fn listProcesses() void {
    out.println("Process List:");
    out.println("PID  Name           State");
    out.println("---  ----           -----");

    for (process_table) |proc| {
        if (proc) |p| {
            const state_str = switch (p.state) {
                ProcessState.Running => "Running",
                ProcessState.Ready => "Ready",
                ProcessState.Waiting => "Waiting",
                ProcessState.Stopped => "Stopped",
                ProcessState.Terminated => "Terminated",
            };
            out.printn(p.id);
            out.print("  ");
            out.print(p.name);
            out.print("           ");
            out.println(state_str);
        }
    }
}

pub fn initProcessManager() void {
    // Initialize process table
    for (process_table, 0..) |_, i| {
        process_table[i] = null;
    }

    next_pid = 1;
    current_process = null;

    out.println("Process manager initialized");
}

pub fn processTest() void {
    @setRuntimeSafety(false);

    // Initialize process manager
    initProcessManager();

    // Create test process
    const process = createProcess("TestProcess") orelse {
        out.println("Failed to create test process");
        return;
    };

    // Simple test program - infinite loop (JMP $)
    const code: [2]u8 = [_]u8{ 0xEB, 0xFE };
    process.program(&code);
}
