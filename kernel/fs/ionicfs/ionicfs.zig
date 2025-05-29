const vfs = @import("vfs");
const out = @import("output");
const str = @import("string");
const sys = @import("system");
const ata = @import("ata");
const alloc = @import("allocator");
const mem = @import("memory");
extern fn memcpy(dest: [*]u8, src: [*]const u8, len: usize) [*]u8;

pub const EMPTY_REGION = 0x0;
pub const DELETED_REGION = 0x1;
pub const DIRECTORY_REGION = 0x2;
pub const FILE_REGION = 0x3;

pub fn detectPartitions(drive: *ata.AtaDrive) [4]vfs.Partition {
    const sector_data = ata.readSectors(drive, 0, 1);
    var sector = mem.Stream(u8).init(&sector_data);
    var partitions: [4]vfs.Partition = undefined;

    sector.seek(400); // Skip to the partition table

    for (0..4) |i| {
        const entry = sector.get(26).?;

        const partition_name = entry[0..18];
        if (partition_name[0] == 0) {
            partitions[i] = vfs.Partition{
                .name = "",
                .start_sector = 0,
                .size = 0,
                .exists = false,
            };
        } else {
            const region_n_data = entry[18..22];
            const region_size_data = entry[22..26];

            const startSector = mem.reinterpretBytes(u32, region_n_data, false).unwrap();
            const size = mem.reinterpretBytes(u32, region_size_data, false).unwrap();

            var dynStr = str.DynamicString.init("");
            for (partition_name) |char| {
                if (char == 0) break;
                dynStr.pushChar(char);
            }

            partitions[i] = vfs.Partition{
                .name = dynStr.snapshot(),
                .start_sector = @as(u64, @intCast(startSector)),
                .size = @as(u64, @intCast(size)),
                .exists = true,
            };
        }
    }

    return partitions;
}

pub fn parseRootDirectory(drive: *ata.AtaDrive, partition: vfs.Partition) vfs.Directory {
    if (!partition.exists) {
        out.println("Partition does not exist.");
        return vfs.Directory{ .region = 0, .entries = &[_]vfs.DirectoryEntry{} };
    }

    const region = @as(u32, @intCast(partition.start_sector));
    return parseDirectory(drive, region, "/");
}

pub fn parseDirectory(drive: *ata.AtaDrive, region: u32, dirName: []const u8) vfs.Directory {
    var entries = mem.Array(vfs.DirectoryEntry).init();
    var current_region: u32 = region;

    while (current_region != 0) {
        const sector_data = ata.readSectors(drive, current_region, 1);

        if (sector_data[0] != DIRECTORY_REGION) {
            out.println("Invalid directory region.");
            return vfs.Directory{ .region = 0, .entries = entries.coerce(), .name = dirName };
        }

        var offset: usize = 1;

        while (offset < 508) {
            if (offset + 25 > 508) break; // Prevent overflow

            const entryType = sector_data[offset];
            if (entryType == 0x0) {
                break;
            }

            if (entryType == DELETED_REGION) {
                offset += 1;
                continue;
            }

            if (entryType != FILE_REGION and entryType != DIRECTORY_REGION) {
                out.println("Unknown entry type in directory.");
                out.print("Found type: ");
                out.printHex(entryType);
                out.println("");
                offset += 1;
                break;
            }

            const isDirectory = entryType == DIRECTORY_REGION;
            offset += 1;

            var lastAccessed: u64 = 0;
            for (0..8) |j| {
                lastAccessed |= @as(u64, sector_data[offset + j]) << @as(u6, @intCast(j * 8));
            }
            offset += 8;

            var lastModified: u64 = 0;
            for (0..8) |j| {
                lastModified |= @as(u64, sector_data[offset + j]) << @as(u6, @intCast(j * 8));
            }
            offset += 8;

            var created: u64 = 0;
            for (0..8) |j| {
                created |= @as(u64, sector_data[offset + j]) << @as(u6, @intCast(j * 8));
            }
            offset += 8;

            var name = str.DynamicString.init("");
            while (offset < 508 and sector_data[offset] != 0) {
                name.pushChar(@as(u8, sector_data[offset]));
                offset += 1;
            }

            if (offset >= 508) {
                out.println("Directory entry name too long.");
                break;
            }

            offset += 1; // Skip the null terminator

            if (offset + 4 > 508) {
                out.println("Directory entry region number overflow.");
                break;
            }

            var entry_region: u32 = 0;
            for (0..4) |j| {
                entry_region |= @as(u32, sector_data[offset + j]) << @as(u5, @intCast(j * 8));
            }
            offset += 4;

            const entry = vfs.DirectoryEntry{
                .name = name.snapshot(),
                .lastAccessed = lastAccessed,
                .lastModified = lastModified,
                .created = created,
                .region = entry_region,
                .isDirectory = isDirectory,
            };
            entries.append(entry);
        }

        current_region = 0;
        for (0..4) |j| {
            current_region |= @as(u32, sector_data[508 + j]) << @as(u5, @intCast(j * 8));
        }
    }

    return vfs.Directory{
        .region = region,
        .entries = entries.coerce(),
        .name = dirName,
    };
}
