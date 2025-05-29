const mem = @import("memory");
const sys = @import("system");
const out = @import("output");
const vfs = @import("vfs");
const pit = @import("pit");

const ATA_PRIMARY_DATA: u16 = 0x1F0;
const ATA_PRIMARY_ERROR: u16 = 0x1F1;
const ATA_PRIMARY_SECTOR_COUNT: u16 = 0x1F2;
const ATA_PRIMARY_LBA_LOW: u16 = 0x1F3;
const ATA_PRIMARY_LBA_MID: u16 = 0x1F4;
const ATA_PRIMARY_LBA_HIGH: u16 = 0x1F5;
const ATA_PRIMARY_DRIVE_HEAD: u16 = 0x1F6;
const ATA_PRIMARY_STATUS: u16 = 0x1F7;
const ATA_PRIMARY_COMMAND: u16 = 0x1F7;
const ATA_PRIMARY_CONTROL: u16 = 0x3F6;

const ATA_CMD_IDENTIFY: u8 = 0xEC;
const ATA_CMD_READ: u8 = 0x20;
const ATA_CMD_WRITE: u8 = 0x30;

const ATA_STATUS_ERR: u8 = 0x01;
const ATA_STATUS_DRQ: u8 = 0x08;
const ATA_STATUS_DF: u8 = 0x20;
const ATA_STATUS_BSY: u8 = 0x80;

const ATA_DRIVE_MASTER: u8 = 0xA0;
const ATA_DRIVE_SLAVE: u8 = 0xB0;

const AtaIdentifyData = struct {
    config: u16,
    cylinders: u16,
    _reserved1: u16,
    heads: u16,
    _reserved2: [2]u16,
    sectors_per_track: u16,
    _reserved3: [3]u16,
    serial: [20]u8,
    _reserved4: [3]u16,
    firmware_version: [8]u8,
    model: [40]u8,
    _reserved5: [33]u16,
    capabilities: u16,
    _reserved6: [8]u16,
    lba_sectors: u32,
    _reserved7: [38]u16,
    command_set: u16,
    _reserved8: [6]u16,
    max_lba: u64,
    _reserved9: [76]u16,
};

pub const AtaDrive = struct {
    is_present: bool,
    is_master: bool,
    model: [41]u8,
    serial: [21]u8,
    firmware: [9]u8,
    size_mb: u32,
    sectors: u32,
    supports_lba: bool,
    supports_lba48: bool,
    fs: usize = 0x01, // Default to IonicFS
    partitions: []const vfs.Partition = undefined,
};

pub const AtaController = struct {
    master: AtaDrive,
    slave: AtaDrive,
};

pub fn makeController() AtaController {
    var controller = AtaController{
        .master = AtaDrive{
            .is_present = false,
            .is_master = true,
            .model = [_]u8{0} ** 41,
            .serial = [_]u8{0} ** 21,
            .firmware = [_]u8{0} ** 9,
            .size_mb = 0,
            .sectors = 0,
            .supports_lba = false,
            .supports_lba48 = false,
        },
        .slave = AtaDrive{
            .is_present = false,
            .is_master = false,
            .model = [_]u8{0} ** 41,
            .serial = [_]u8{0} ** 21,
            .firmware = [_]u8{0} ** 9,
            .size_mb = 0,
            .sectors = 0,
            .supports_lba = false,
            .supports_lba48 = false,
        },
    };
    detectDrive(&controller, true);
    detectDrive(&controller, false);

    return controller;
}

fn detectDrive(controller: *AtaController, is_master: bool) void {
    const drive_select = if (is_master) ATA_DRIVE_MASTER else ATA_DRIVE_SLAVE;
    var drive = if (is_master) &controller.master else &controller.slave;

    sys.outb(ATA_PRIMARY_DRIVE_HEAD, drive_select);

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        _ = sys.inb(ATA_PRIMARY_STATUS);
    }

    sys.outb(ATA_PRIMARY_COMMAND, ATA_CMD_IDENTIFY);

    const status = sys.inb(ATA_PRIMARY_STATUS);
    if (status == 0) {
        drive.is_present = false;
        return;
    }

    while (sys.inb(ATA_PRIMARY_STATUS) & ATA_STATUS_BSY != 0) {}

    const status2 = sys.inb(ATA_PRIMARY_STATUS);
    if (status2 & ATA_STATUS_ERR != 0 or status2 & ATA_STATUS_DF != 0) {
        drive.is_present = false;
        return;
    }

    while ((sys.inb(ATA_PRIMARY_STATUS) & ATA_STATUS_DRQ) == 0) {
        if (sys.inb(ATA_PRIMARY_STATUS) & ATA_STATUS_ERR != 0) {
            drive.is_present = false;
            return;
        }
    }

    var identify_data: [256]u16 = undefined;
    for (0..256) |j| {
        identify_data[j] = sys.inw(ATA_PRIMARY_DATA);
    }

    drive.is_present = true;
    drive.is_master = is_master;

    var model_chars: [40]u8 = undefined;
    for (0..20) |idx| {
        const word = identify_data[27 + idx];
        model_chars[idx * 2] = @truncate((word >> 8) & 0xFF);
        model_chars[idx * 2 + 1] = @truncate(word & 0xFF);
    }

    copyAndTrim(&drive.model, &model_chars);

    var serial_chars: [20]u8 = undefined;
    for (0..10) |idx| {
        const word = identify_data[10 + idx];
        serial_chars[idx * 2] = @truncate((word >> 8) & 0xFF);
        serial_chars[idx * 2 + 1] = @truncate(word & 0xFF);
    }
    copyAndTrim(&drive.serial, &serial_chars);

    var firmware_chars: [8]u8 = undefined;
    for (0..4) |idx| {
        const word = identify_data[23 + idx];
        firmware_chars[idx * 2] = @truncate((word >> 8) & 0xFF);
        firmware_chars[idx * 2 + 1] = @truncate(word & 0xFF);
    }
    copyAndTrim(&drive.firmware, &firmware_chars);

    drive.supports_lba = (identify_data[49] & 0x200) != 0;
    drive.supports_lba48 = (identify_data[83] & 0x200) != 0;

    if (drive.supports_lba48) {
        const lba_sectors: u64 =
            @as(u64, identify_data[100]) |
            (@as(u64, identify_data[101]) << 16) |
            (@as(u64, identify_data[102]) << 32) |
            (@as(u64, identify_data[103]) << 48);
        drive.sectors = @truncate(lba_sectors);
    } else if (drive.supports_lba) {
        const lba_sectors: u32 =
            @as(u32, identify_data[60]) |
            (@as(u32, identify_data[61]) << 16);
        drive.sectors = @truncate(lba_sectors);
    } else {
        const cylinders = identify_data[1];
        const heads = identify_data[3];
        const sectors_per_track = identify_data[6];
        drive.sectors = @as(u32, cylinders) * @as(u32, heads) * @as(u32, sectors_per_track);
    }

    drive.size_mb = drive.sectors / 2048;
}

fn copyAndTrim(dest: []u8, src: []const u8) void {
    @setRuntimeSafety(false);
    var i: usize = 0;
    while (i < src.len and i < dest.len - 1) : (i += 1) {
        dest[i] = src[i];
    }

    dest[i] = 0;

    while (i > 0 and (dest[i - 1] == ' ' or dest[i - 1] == 0)) : (i -= 1) {
        dest[i - 1] = 0;
    }
}

pub fn printDeviceInfo(drive: *AtaDrive) void {
    out.print("======= ");
    if (drive.is_master) {
        out.print("Primary");
    } else {
        out.print("Secondary");
    }
    out.print(" Drive =======\n");
    if (!drive.is_present) {
        out.print("Drive not present\n");
    }

    out.print("Model: ");
    out.print(&drive.model);
    out.print("\n");
    out.print("Serial: ");
    out.print(&drive.serial);
    out.print("\n");
    out.print("Firmware: ");
    out.print(&drive.firmware);
    out.print("\n");
    out.print("Size: ");
    out.printn(drive.size_mb);
    out.print(" MB\n");
    out.print("Sectors: ");
    out.printHex(drive.sectors);
    out.print("\n");
    out.print("Supports LBA: ");
    if (drive.supports_lba) {
        out.print("Yes\n");
    } else {
        out.print("No\n");
    }
    out.print("Supports LBA48: ");
    if (drive.supports_lba48) {
        out.print("Yes\n");
    } else {
        out.print("No\n");
    }

    const fs = vfs.detectFileSystem(drive);
    out.print("File System: ");
    out.println(fs);
}

pub fn readSectors(drive: *const AtaDrive, lba: u32, comptime sectors: comptime_int) [sectors * 512]u8 {
    if (sectors == 0) {
        return [_]u8{0} ** (sectors * 512);
    }

    if (!drive.is_present) {
        sys.panic("Tried to read from a drive that is not present");
        return [_]u8{0} ** (sectors * 512);
    }

    if (lba + sectors > drive.sectors) {
        sys.panic("Tried to read past the end of the drive");
        return [_]u8{0} ** (sectors * 512);
    }

    var buffer: [sectors * 512]u8 = [_]u8{0} ** (sectors * 512);

    var drive_select = (if (drive.is_master) ATA_DRIVE_MASTER else ATA_DRIVE_SLAVE) | 0x40;
    if (drive.supports_lba48) {
        drive_select |= 0x80;
    }

    while (sys.inb(ATA_PRIMARY_STATUS) & ATA_STATUS_BSY != 0) {}

    sys.outb(ATA_PRIMARY_DRIVE_HEAD, drive_select);
    sys.outb(ATA_PRIMARY_SECTOR_COUNT, sectors);
    sys.outb(ATA_PRIMARY_LBA_LOW, @truncate(lba & 0xFF));
    sys.outb(ATA_PRIMARY_LBA_MID, @truncate((lba >> 8) & 0xFF));
    sys.outb(ATA_PRIMARY_LBA_HIGH, @truncate((lba >> 16) & 0xFF));

    sys.outb(ATA_PRIMARY_COMMAND, ATA_CMD_READ);

    var sector: usize = 0;
    while (sector < sectors) : (sector += 1) {
        while (true) {
            const status = sys.inb(ATA_PRIMARY_STATUS);
            if (status & ATA_STATUS_ERR != 0) {
                const err = sys.inb(ATA_PRIMARY_ERROR);

                if (err & 0x80 != 0) {
                    sys.panic("ATA error: Bad block detected (BBK)");
                } else if (err & 0x40 != 0) {
                    sys.panic("ATA error: Uncorrectable data error (UNC)");
                } else if (err & 0x20 != 0) {
                    sys.panic("ATA error: Media changed (MC)");
                } else if (err & 0x10 != 0) {
                    sys.panic("ATA error: ID not found (IDNF)");
                } else if (err & 0x08 != 0) {
                    sys.panic("ATA error: Media change request (MCR)");
                } else if (err & 0x04 != 0) {
                    sys.panic("ATA error: Command aborted (ABRT)");
                } else if (err & 0x02 != 0) {
                    sys.panic("ATA error: Track 0 not found (TK0NF)");
                } else if (err & 0x01 != 0) {
                    sys.panic("ATA error: Address mark not found (AMNF)");
                } else {
                    sys.panic("ATA error: Unknown error");
                }
            }

            if (status & ATA_STATUS_BSY == 0 and status & ATA_STATUS_DRQ != 0) {
                break;
            }
        }

        const offset = sector * 512;
        var word_idx: usize = 0;
        while (word_idx < 256) : (word_idx += 1) {
            const word = sys.inw(ATA_PRIMARY_DATA);
            buffer[offset + word_idx * 2] = @truncate(word & 0xFF);
            buffer[offset + word_idx * 2 + 1] = @truncate((word >> 8) & 0xFF);
        }
    }
    return buffer;
}

pub fn writeSectors(drive: *const AtaDrive, lba: u32, sectors: u8, buffer: [*]u8) void {
    @setRuntimeSafety(false);
    if (sectors == 0) {
        return;
    }

    if (!drive.is_present) {
        sys.panic("Tryied to write to a drive that is not present");
        return;
    }

    if (lba + sectors > drive.sectors) {
        sys.panic("Tried to write past the end of the drive");
        return;
    }

    const drive_select = if (drive.is_master) ATA_DRIVE_MASTER else ATA_DRIVE_SLAVE;

    while (sys.inb(ATA_PRIMARY_STATUS) & ATA_STATUS_BSY != 0) {}

    sys.outb(ATA_PRIMARY_DRIVE_HEAD, drive_select);
    sys.outb(ATA_PRIMARY_SECTOR_COUNT, sectors);
    sys.outb(ATA_PRIMARY_LBA_LOW, @truncate(lba & 0xFF));
    sys.outb(ATA_PRIMARY_LBA_MID, @truncate((lba >> 8) & 0xFF));
    sys.outb(ATA_PRIMARY_LBA_HIGH, @truncate((lba >> 16) & 0xFF));

    sys.outb(ATA_PRIMARY_COMMAND, ATA_CMD_WRITE);

    var sector: usize = 0;
    while (sector < sectors) : (sector += 1) {
        while (true) {
            const status = sys.inb(ATA_PRIMARY_STATUS);
            if (status & ATA_STATUS_ERR != 0) {
                sys.panic("Error writing to drive");
                return;
            }
            if (status & ATA_STATUS_BSY == 0 and status & ATA_STATUS_DRQ != 0) {
                break;
            }
        }

        const offset = sector * 512;
        var word_idx: usize = 0;
        while (word_idx < 256) : (word_idx += 1) {
            const word = @as(u16, buffer[offset + word_idx * 2]) | (@as(u16, buffer[offset + word_idx * 2 + 1]) << 8);
            sys.outw(ATA_PRIMARY_DATA, word);
        }
    }

    sys.outb(ATA_PRIMARY_COMMAND, 0xE7);
    while (sys.inb(ATA_PRIMARY_STATUS) & ATA_STATUS_BSY != 0) {}
}
