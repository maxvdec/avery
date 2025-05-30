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

pub fn traverseDirectory(drive: *ata.AtaDrive, dirName: []const u8, partition: u32) u32 {
    @setRuntimeSafety(false);
    const partition_data = detectPartitions(drive);
    if (!partition_data[partition].exists) {
        out.println("Partition does not exist.");
        return 0;
    }

    var entries = parseRootDirectory(drive, partition_data[partition]);
    var pathItems = mem.Array(str.String).init();
    var path = dirName;
    const delim: u8 = '/';
    var pos: ?usize = 0;
    while (true) {
        pos = mem.find(u8, path, delim);
        if (pos == null) {
            break;
        }
        const item = path[0..pos.?];
        pathItems.append(str.String.fromRuntime(item));
        path = path[pos.? + 1 ..];
    }
    pathItems.append(str.makeRuntime(path));
    var found: usize = 0;
    while (found < pathItems.len) : (found += 1) {
        const currentPath = pathItems.get(found).?;
        if (currentPath.isEqualTo(str.make("."))) {
            continue;
        }
        var foundEntry = false;
        for (entries.entries) |entry| {
            if (mem.compareBytes(u8, entry.name, currentPath.coerce()) and entry.isDirectory) {
                foundEntry = true;
                entries = parseDirectory(drive, entry.region, currentPath.coerce());
                break;
            }
        }
        if (!foundEntry) {
            out.print("Directory not found: ");
            out.println(currentPath.coerce());
            return 0;
        }
    }

    if (found == pathItems.len) {
        for (entries.entries) |entry| {
            if (mem.compareBytes(u8, entry.name, pathItems.get(found - 1).?.iterate())) {
                return entry.region;
            }
        }
    }
    out.print("Directory not found: ");
    out.println(pathItems.get(found - 1).?.iterate());
    return 0;
}

pub fn findFileInDirectory(drive: *ata.AtaDrive, fileName: []const u8, region: u32) u32 {
    @setRuntimeSafety(false);

    var entries = parseDirectory(drive, region, ".");
    var found: usize = 0;
    while (found < entries.entries.len) : (found += 1) {
        const currentPath = entries.entries[found].name;
        if (mem.compareBytes(u8, currentPath, ".")) {
            continue;
        }
        var foundEntry = false;
        for (entries.entries) |entry| {
            if (mem.compareBytes(u8, entry.name, currentPath) and entry.isDirectory) {
                foundEntry = true;
                entries = parseDirectory(drive, entry.region, currentPath);
                break;
            } else if (mem.compareBytes(u8, entry.name, fileName) and !entry.isDirectory) {
                foundEntry = true;
                return entry.region;
            }
        }
        if (!foundEntry) {
            out.print("Directory not found: ");
            out.println(currentPath);
            return 0;
        }
    }
    return 0;
}

pub fn readFile(drive: *ata.AtaDrive, fileName: []const u8, partition: u32) ?[]const u8 {
    @setRuntimeSafety(false);
    const partition_data = detectPartitions(drive);
    if (!partition_data[partition].exists) {
        out.println("Partition does not exist.");
        return null;
    }

    var filePath: []const u8 = fileName;
    var dirPath: []const u8 = "";
    var bareFileName: []const u8 = "";

    const lastSlashIndex = mem.findLast(u8, filePath, '/');
    if (lastSlashIndex != null) {
        dirPath = filePath[0..lastSlashIndex.?];
        bareFileName = filePath[lastSlashIndex.? + 1 ..];
    } else {
        bareFileName = filePath;
    }

    const dirRegion = traverseDirectory(drive, dirPath, partition);
    var region = findFileInDirectory(drive, bareFileName, dirRegion);
    if (region == 0) {
        out.print("File not found: ");
        out.println(bareFileName);
        return null;
    }
    const sector_data = ata.readSectors(drive, region, 1);
    var sector = mem.Stream(u8).init(&sector_data);
    var buffer = mem.Buffer(u8, 256).init();
    while (true) {
        const byte = sector.get(1).?[0];
        if (byte == FILE_REGION) {
            const fileData = sector.get(507).?;
            buffer.push(fileData);
            var nextRegion: u32 = 0;
            const regionData = sector.get(4).?;
            for (0..4) |j| {
                nextRegion |= @as(u32, regionData[j]) << @as(u5, @intCast(j * 8));
            }
            if (nextRegion == 0) {
                break;
            }
            region = nextRegion;
            const nextSectorData = ata.readSectors(drive, region, 1);
            sector = mem.Stream(u8).init(&nextSectorData);
        }
    }

    if (buffer.len == 0) {
        out.println("File is empty.");
        return null;
    }
    return buffer.coerce();
}
