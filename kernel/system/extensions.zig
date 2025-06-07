const temrinal = @import("terminal");
const out = @import("output");

pub const KernelExtensions = struct {
    framebufferTerminal: u32 = 0x00,

    pub fn init() KernelExtensions {
        return KernelExtensions{};
    }

    pub fn requestTerminal(self: *KernelExtensions) void {
        out.switchToSerial();
        self.framebufferTerminal = @intFromPtr(out.term);
    }
};
