const temrinal = @import("terminal");
const out = @import("output");
const proc = @import("process");

pub const KernelExtensions = struct {
    framebufferTerminal: u32 = 0x00,
    mainProcess: u32 = 0x00,

    pub fn init() KernelExtensions {
        return KernelExtensions{};
    }

    pub fn requestTerminal(self: *KernelExtensions) void {
        self.framebufferTerminal = @intFromPtr(out.term);
    }

    pub fn addProcess(self: *KernelExtensions, process: *proc.Process) void {
        self.mainProcess = @intFromPtr(process);
    }
};
