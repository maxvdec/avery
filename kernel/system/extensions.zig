const temrinal = @import("terminal");
const out = @import("output");
const proc = @import("process");
const sch = @import("scheduler");
const ata = @import("ata");
const kalloc = @import("kern_allocator");

pub const KernelExtensions = struct {
    framebufferTerminal: u32 = 0x00,
    mainProcess: u32 = 0x00,
    scheduler: u32 = 0x00,
    ataDrive: u32 = 0x00,
    kernelAllocSnapshot: u32 = 0x00,

    pub fn init() KernelExtensions {
        return KernelExtensions{};
    }

    pub fn requestTerminal(self: *KernelExtensions) void {
        self.framebufferTerminal = @intFromPtr(out.term);
    }

    pub fn addProcess(self: *KernelExtensions, process: *proc.Process) void {
        self.mainProcess = @intFromPtr(process);
    }

    pub fn setScheduler(self: *KernelExtensions, scheduler: *sch.Scheduler) void {
        self.scheduler = @intFromPtr(scheduler);
    }

    pub fn setAtaDrive(self: *KernelExtensions, ataDrive: *ata.AtaDrive) void {
        self.ataDrive = @intFromPtr(ataDrive);
    }

    pub fn updateKernelAlloc(self: *KernelExtensions) void {
        const ksnapshot = kalloc.storeKernel(kalloc.Snapshot);
        self.kernelAllocSnapshot = @intFromPtr(ksnapshot);
        ksnapshot.* = kalloc.takeSnapshot();
    }
};
