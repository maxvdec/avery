const terminal = @import("terminal");
const framebuffer = @import("framebuffer");
const mem = @import("memory");
const vfs = @import("vfs");
const ata = @import("ata");
const multiboot2 = @import("multiboot2");
const out = @import("output");

pub fn setupInterfaces(term: terminal.FramebufferTerminal, drive: *ata.AtaDrive) void {
    @setRuntimeSafety(false);
    const bytes = mem.reinterpretToBytes(multiboot2.FramebufferTag, term.framebuffer.framebufferTag);
    const framebufferRoute: []const u8 = "/dev/stdout";
    if (!vfs.fileExists(drive, framebufferRoute, 0)) {
        if (!vfs.directoryExists(drive, "dev", 0)) {
            _ = vfs.makeNewDirectory(drive, "dev", 0);
        }
        _ = vfs.createFile(drive, framebufferRoute, 0);
    }
    _ = vfs.writeToFile(drive, framebufferRoute, bytes, 0);
}
