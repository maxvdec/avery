const ata = @import("ata");
const mem = @import("memory");
const sys = @import("system");
const out = @import("output");
const alloc = @import("allocator");
const ionicfs = @import("ionicfs");
const str = @import("string");
const rtc = @import("rtc");

pub const Partition = struct {
    name: []const u8,
    start_sector: u64,
    size: u64,
    exists: bool,
};

pub const DirectoryEntry = struct {
    name: []const u8,
    lastAccessed: u64,
    lastModified: u64,
    created: u64,
    region: u32,
    isDirectory: bool,
};

pub const Directory = struct {
    region: u32,
    name: []const u8 = "",
    entries: []DirectoryEntry,
};

pub const SupportedFileSystems = enum(usize) {
    Undefined = 0,
    IonicFS = 1,
};

pub fn detectFileSystem(drive: *ata.AtaDrive) []const u8 {
    @setRuntimeSafety(false);
    if (!drive.is_present) {
        return "Undefined";
    }
    const sector = ata.readSectors(drive, 0, 1);
    const signature = [5]u8{ sector[504], sector[505], sector[506], sector[507], sector[508] };
    if (mem.compareBytes(u8, &signature, "IONFS")) {
        const version = [3]u8{ sector[509], sector[510], sector[511] };
        var fs_name = str.DynamicString.init("IonicFS ");
        fs_name.pushChar(version[0]);
        fs_name.pushChar('.');
        fs_name.pushChar(version[1]);
        fs_name.pushChar('.');
        fs_name.pushChar(version[2]);
        drive.fs = @intFromEnum(SupportedFileSystems.IonicFS);
        return fs_name.snapshot();
    } else {
        drive.fs = @intFromEnum(SupportedFileSystems.Undefined);
    }
    return "";
}

pub fn getRootDirectory(drive: *ata.AtaDrive, partitionNumber: u8) Directory {
    @setRuntimeSafety(false);
    _ = detectPartitions(drive);
    if (!drive.is_present) {
        out.println("No drive detected.");
        return Directory{ .region = 0, .name = "", .entries = &[_]DirectoryEntry{} };
    }

    if (partitionNumber >= drive.partitions.len) {
        out.println("Invalid partition number.");
        out.printn(partitionNumber);
        out.print(" (Max: ");
        out.printn(drive.partitions.len - 1);
        out.println(")");
        out.println("Returning empty directory.");
        return Directory{ .region = 0, .name = "", .entries = &[_]DirectoryEntry{} };
    }

    const partition = drive.partitions[partitionNumber];
    if (!partition.exists) {
        out.println("Partition does not exist.");
        return Directory{ .region = 0, .name = "", .entries = &[_]DirectoryEntry{} };
    }

    switch (drive.fs) {
        0x01 => {
            return ionicfs.parseRootDirectory(drive, partition);
        },
        else => {
            out.println("Unsupported file system detected.");
            return Directory{ .region = 0, .name = "", .entries = &[_]DirectoryEntry{} };
        },
    }
}

pub fn printDirectory(dir: Directory) void {
    @setRuntimeSafety(false);
    out.print("Directory ");
    out.print(dir.name);
    out.print(" (Region: ");
    out.printn(dir.region);
    out.println("):");
    if (dir.entries.len == 0) {
        out.println("  No entries found.");
        return;
    }
    for (dir.entries) |entry| {
        out.print(entry.name);
        if (entry.isDirectory) {
            out.print("/");
        }
        out.print(" (Region: ");
        out.printHex(entry.region);
        out.print(", Last Accessed: ");
        const lastAccessedStr = rtc.formatDateTime(rtc.unixToDateTime(entry.lastAccessed));
        out.print(lastAccessedStr);
        out.print(", Last Modified: ");
        const lastModifiedStr = rtc.formatDateTime(rtc.unixToDateTime(entry.lastModified));
        out.print(lastModifiedStr);
        out.print(", Created: ");
        const createdStr = rtc.formatDateTime(rtc.unixToDateTime(entry.created));
        out.print(createdStr);
        out.println(")");
    }
}

pub fn printPartitions(drive: *ata.AtaDrive) void {
    @setRuntimeSafety(false);
    if (!drive.is_present) {
        out.println("No drive detected.");
        return;
    }

    if (drive.partitions.len == 0) {
        _ = detectPartitions(drive);
    }

    out.print("Partitions on the ");
    if (drive.is_master) {
        out.print("Primary ");
    } else {
        out.print("Secondary ");
    }
    out.print(" Drive (");
    out.print(&drive.model);
    out.println("):");
    for (drive.partitions) |partition| {
        if (!partition.exists) {
            continue;
        }
        out.print("  Name: ");
        const nameStr = str.makeRuntime(partition.name);
        out.printstr(nameStr.trim());
        out.print(", Start Sector: ");
        out.printHex(partition.start_sector);
        out.print(", Size: ");
        out.printU64(partition.size * 512);
        out.println(" bytes");
    }
}

pub fn detectPartitions(drive: *ata.AtaDrive) []const Partition {
    if (!drive.is_present) {
        out.println("No drive detected.");
        return &[_]Partition{};
    }

    if (drive.partitions.len > 0) {
        return drive.partitions;
    }
    switch (drive.fs) {
        0x01 => {
            const parts_data = ionicfs.detectPartitions(drive);
            if (parts_data.len == 0) {
                out.println("No partitions found on the drive.");
                return &[_]Partition{};
            }
            const parts = alloc.storeMany(Partition, 4);
            mem.copy(Partition, parts, &parts_data, parts_data.len);
            drive.partitions = parts[0..parts_data.len];
            return parts[0..parts_data.len];
        },
        else => {
            out.println("Unsupported file system detected.");
            return &[_]Partition{};
        },
    }
}
