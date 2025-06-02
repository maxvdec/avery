const terminal = @import("terminal");
const framebuffer = @import("framebuffer");
const mem = @import("memory");
const vfs = @import("vfs");
const ata = @import("ata");
const multiboot2 = @import("multiboot2");
const out = @import("output");
const str = @import("string");

pub fn setupInterfaces(term: *terminal.FramebufferTerminal, drive: *ata.AtaDrive) void {
    @setRuntimeSafety(false);
    const n64Bytes = @intFromPtr(term);
    const bytes: []const u8 = &str.u64ToBytes(n64Bytes);
    out.printHex(n64Bytes);
    out.println("");
    const framebufferRoute: []const u8 = "/dev/stdout";
    if (!vfs.fileExists(drive, framebufferRoute, 0)) {
        if (!vfs.directoryExists(drive, "dev", 0)) {
            _ = vfs.makeNewDirectory(drive, "dev", 0);
        }
        _ = vfs.createFile(drive, framebufferRoute, 0);
    }
    _ = vfs.writeToFile(drive, framebufferRoute, bytes, 0);
}
