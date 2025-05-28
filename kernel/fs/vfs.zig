const ata = @import("ata");
const mem = @import("memory");
const str = @import("string");
const sys = @import("system");
const out = @import("output");

pub fn detectFileSystem(drive: *const ata.AtaDrive) []const u8 {
    if (!drive.is_present) {
        return "Undefined";
    }
    const sector = ata.readSectors(drive, 0, 1);
    out.printchar(sector[504]);
    out.printchar(sector[505]);
    out.printchar(sector[506]);
    out.printchar(sector[507]);
    out.printchar(sector[508]);
    return "";
}
