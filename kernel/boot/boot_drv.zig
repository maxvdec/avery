const driver = @import("drv_load");
const ata = @import("ata");
const out = @import("output");
const vfs = @import("vfs");
const mem = @import("memory");
const dir_structure = @import("dir_structure");
const path = @import("path");
const alloc = @import("allocator");

pub fn findDrivers(drive: *ata.AtaDrive) mem.Array(driver.Driver) {
    @setRuntimeSafety(false);
    const dir = vfs.getDirectory(drive, &dir_structure.DRIVERS, 0);
    var drivers = mem.Array(driver.Driver).init();
    var buff: [1024]u8 = undefined;
    for (dir.entries) |entry| {
        if (!entry.isDirectory) {
            var parts = mem.split(entry.name, '.');
            const extension = parts.last();
            if (mem.compareBytes(u8, extension.?, "drv")) {
                const fullPath = path.joinPaths(&dir_structure.DRIVERS, entry.name);
                for (&buff) |*byte| {
                    byte.* = 0;
                }
                for (0..fullPath.len) |i| {
                    buff[i] = fullPath[i];
                }
                const contents = vfs.readFile(drive, 0, buff[0..fullPath.len]);
                if (contents == null) {
                    out.print("Could not read driver file");
                    continue;
                }
                const drv = driver.loadDriver(fullPath, contents.?);
                if (drv == null) {
                    out.print("Could not load driver");
                    continue;
                }
                drivers.append(drv.?.*);
            }
        }
    }

    return drivers;
}
