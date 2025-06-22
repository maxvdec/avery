const arf = @import("arf");
const out = @import("output");
const kalloc = @import("kern_allocator");
const ata = @import("ata");
const vfs = @import("vfs");
const mem = @import("memory");

pub const DriverType = enum(u8) {
    Utility = 0x0,
    Stream = 0x1,
    Block = 0x2,
    FileSystem = 0x3,
    MemoryTechnology = 0x4,
    NetworkInterface = 0x5,
    ProtocolStack = 0x6,
    Terminal = 0x7,
    Audio = 0x8,
    Video = 0x9,
    Input = 0xA,
    HumanInterfaceDevice = 0xB,
    PowerSupply = 0xC,
    Thermal = 0xD,
    Bus = 0xE,
};

fn typeFromByte(byte: u8) DriverType {
    return switch (byte) {
        0x0 => DriverType.Utility,
        0x1 => DriverType.Stream,
        0x2 => DriverType.Block,
        0x3 => DriverType.FileSystem,
        0x4 => DriverType.MemoryTechnology,
        0x5 => DriverType.NetworkInterface,
        0x6 => DriverType.ProtocolStack,
        0x7 => DriverType.Terminal,
        0x8 => DriverType.Audio,
        0x9 => DriverType.Video,
        0xA => DriverType.Input,
        0xB => DriverType.HumanInterfaceDevice,
        0xC => DriverType.PowerSupply,
        0xD => DriverType.Thermal,
        0xE => DriverType.Bus,
        else => DriverType.Utility,
    };
}

pub const Driver = struct {
    name: []const u8,
    description: []const u8,
    version: [3]u8,
    path: []const u8,
    type: DriverType,

    spec_version: []const u8,
    arf_data: []const u8,

    hash: []const u8,

    manufacturer: u16,
    device_id: u16,
    subsystem_id: u8,
};

pub fn loadDriver(path: []const u8, data: []const u8) ?*Driver {
    out.preserveMode();
    defer out.restoreMode();
    out.switchToSerial();
    const driver = kalloc.storeKernel(Driver);
    var stream = mem.Stream(u8).init(data);
    const header = stream.get(8);

    if (!mem.compareBytes(u8, header.?[0..6], "AVDRIV")) {
        out.print("Driver at path ");
        out.print(path);
        out.print(" has not a valid header. Skipping...");
        return null;
    }

    driver.spec_version = header.?[6..];

    const type_byte = stream.get(1).?[0];
    driver.type = typeFromByte(type_byte);

    const manufacturer = stream.get(2).?;
    driver.manufacturer = mem.reinterpretBytes(u16, manufacturer, true).unwrap();
    const device_id = stream.get(2).?;
    driver.device_id = mem.reinterpretBytes(u16, device_id, true).unwrap();
    const subsystem_id = stream.get(1).?;
    driver.subsystem_id = subsystem_id[0];

    const driver_name = stream.getUntil(0x0).?;
    driver.name = driver_name;

    const driver_description = stream.getUntil(0x0).?;
    driver.description = driver_description;

    const driver_version = stream.get(3).?;
    driver.version = driver_version[0..3].*;

    const hash = stream.getUntil(0x0).?;
    driver.hash = hash;

    const arf_data = stream.getRemaining();
    driver.arf_data = arf_data;

    return driver;
}
