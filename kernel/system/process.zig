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

pub const ProcessContext = packed struct {
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
};

const USER_STACK_SIZE: usize = 2 * vmm.PAGE_SIZE;

const Process = struct {
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

        return vmm.USER_CODE_VADDR;
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

        return proc;
    }
};

var current_process: ?*Process = null;
var process_list: [256]Process = &[_]Process{};
var next_pid: u32 = 1;

pub fn processTest() void {
    @setRuntimeSafety(false);

    const bytes = [_]u8{
        0xEB, 0xFE, // Infinite loop: jmp to the same instruction
    };

    _ = Process.create_process(&bytes) orelse {
        out.println("Failed to create process.");
        return;
    };
}
