const vfs = @import("vfs");
const out = @import("output");
const str = @import("string");
const sys = @import("system");
const ata = @import("ata");
const alloc = @import("allocator");
const mem = @import("memory");
const path = @import("path");
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
            if (offset + 25 > 508) break;

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

            const buf = alloc.duplicate(u8, name.snapshot());
            if (buf == null) {
                out.println("Memory allocation failed for directory entry name.");
                return vfs.Directory{ .region = 0, .entries = entries.coerce(), .name = dirName };
            }

            const entry = vfs.DirectoryEntry{
                .name = buf.?[0..name.length()],
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
    var buffer: [256]u8 = undefined;
    for (0..buffer.len) |i| {
        if (i < dirName.len) {
            buffer[i] = dirName[i];
        } else {
            buffer[i] = 0;
        }
    }
    if (!drive.is_present) {
        out.println("No drive detected.");
        return 0;
    }
    const partition_data = detectPartitions(drive);
    if (partition >= partition_data.len) {
        out.println("Partition number out of bounds.");
        return 0;
    }
    if (!partition_data[partition].exists) {
        out.println("Partition does not exist.");
        return 0;
    }
    sys.delay(100);
    const components = path.getPathComponents(buffer[0..dirName.len]);
    var current_region: u32 = @intCast(partition_data[partition].start_sector);
    for (components) |component| {
        const componentStr: []const u8 = component[0 .. mem.find(u8, &component, 0) orelse component.len];
        if (mem.isEmpty(u8, componentStr)) {
            out.println("Empty directory component.");
            continue;
        }
        const region = findFileInDirectory(drive, componentStr, current_region);
        if (region == 0) {
            out.print("Directory not found: ");
            out.println(componentStr);
            return 0;
        }
        current_region = region;
    }
    return current_region;
}

pub fn getDirectoryRegion(drive: *ata.AtaDrive, dirPath: []const u8, partition: u32) u32 {
    var buffer: [256]u8 = undefined;
    for (0..buffer.len) |i| {
        if (i < dirPath.len) {
            buffer[i] = dirPath[i];
        } else {
            buffer[i] = 0;
        }
    }
    return traverseDirectory(drive, buffer[0..dirPath.len], partition);
}

pub fn findFileInDirectory(drive: *ata.AtaDrive, fileName: []const u8, region: u32) u32 {
    @setRuntimeSafety(false);

    const entries = parseDirectory(drive, region, ".");

    for (entries.entries) |entry| {
        if (mem.compareBytes(u8, entry.name, fileName)) {
            return entry.region;
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
        bareFileName = fileName;
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
    var buffer = mem.Buffer(u8, 507).init();
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
    const data = buffer.coerce();
    return data;
}

pub fn findFreeRegion(drive: *ata.AtaDrive, partition: u32, ignore: []u32) u32 {
    @setRuntimeSafety(false);
    var currentRegion: u32 = @as(u32, @intCast(drive.partitions[partition].start_sector));
    while (currentRegion < drive.partitions[partition].start_sector + drive.partitions[partition].size) {
        const sector_data = ata.readSectors(drive, currentRegion, 1);
        if (sector_data[0] == EMPTY_REGION or sector_data[0] == DELETED_REGION) {
            var isFree = true;
            for (ignore) |ignoredRegion| {
                if (ignoredRegion == currentRegion) {
                    isFree = false;
                    break;
                }
            }
            if (isFree) {
                return currentRegion;
            }
        }
        currentRegion += 1;
    }
    return 0;
}

pub fn findFreeDirectoryEntry(drive: *ata.AtaDrive, region: u32, sizeAtLeast: u32) u64 {
    @setRuntimeSafety(false);
    var currentRegion: u32 = region;
    const bufferData = ata.readSectors(drive, currentRegion, 1);
    var buffer = mem.Stream(u8).init(&bufferData);
    var offset: usize = 1;
    _ = buffer.get(1); // Skip the first byte which is the region type
    while (true) {
        const entryType = buffer.get(1).?[0];
        offset += 1;
        if (entryType == EMPTY_REGION or entryType == DELETED_REGION) {
            if (offset + sizeAtLeast > 508) {
                var continueRegion: u32 = 0;
                for (0..4) |j| {
                    continueRegion |= @as(u32, buffer.get(4 + j).?[0]) << @as(u5, @intCast(j * 8));
                }
                if (continueRegion == 0) {
                    var sectorData = ata.readSectors(drive, currentRegion, 1);
                    const nextRegion = findFreeRegion(drive, 0, &[_]u32{});
                    if (nextRegion == 0) {
                        out.println("No free region found.");
                        return 0;
                    }
                    sectorData[508] = @as(u8, nextRegion & 0xFF);
                    sectorData[509] = @as(u8, (nextRegion >> 8) & 0xFF);
                    sectorData[510] = @as(u8, (nextRegion >> 16) & 0xFF);
                    sectorData[511] = @as(u8, (nextRegion >> 24) & 0xFF);
                    ata.writeSectors(drive, currentRegion, &sectorData);
                    var newSector = [_]u8{0} ** 512;
                    newSector[0] = DIRECTORY_REGION;
                    ata.writeSectors(drive, nextRegion, &newSector);
                    return @intCast(nextRegion * 512 + 1);
                } else {
                    const newBufferData = ata.readSectors(drive, continueRegion, 1);
                    buffer = mem.Stream(u8).init(&newBufferData);
                    currentRegion = continueRegion;
                    offset = 1;
                    continue;
                }
            } else {
                return @intCast(currentRegion * 512 + (offset - 1));
            }
        }
        offset += 24;
        while (offset < 508 and buffer.get(1).?[0] != 0) {
            offset += 1; // Skip the name
        }
        offset += 1; // Skip the null terminator
        offset += 4; // Skip the region number
    }
    return 0;
}

pub fn createDirectory(drive: *ata.AtaDrive, dirName: []const u8, partition: u32) void {
    @setRuntimeSafety(false);
    if (!drive.is_present) {
        out.println("No drive detected.");
        return;
    }
    const partition_data = detectPartitions(drive);
    if (partition >= partition_data.len) {
        out.println("Partition number out of bounds.");
        return;
    }
    if (!partition_data[partition].exists) {
        out.println("Partition does not exist.");
        return;
    }

    var withoutLastComponent: []const u8 = "";
    var directoryName: []const u8 = "";

    const lastSlashIndex = mem.findLast(u8, dirName, '/');
    if (lastSlashIndex == null) {
        withoutLastComponent = "";
        directoryName = dirName;
    } else {
        withoutLastComponent = dirName[0..lastSlashIndex.?];
        directoryName = dirName[lastSlashIndex.? + 1 ..];
    }

    const parentRegion = traverseDirectory(drive, withoutLastComponent, partition);
    var writeStream = ata.WriteStream.init(drive);

    if (parentRegion == 0) {
        out.print("Parent directory not found: ");
        out.println(withoutLastComponent);
        return;
    } else {
        const size = 1 + 24 + directoryName.len + 1 + 4; // Type + timestamps + name + null terminator + region number
        const freeEntry = findFreeDirectoryEntry(drive, parentRegion, size);
        if (freeEntry == 0) {
            out.println("No free directory entry found.");
            return;
        }
        writeStream.seek(freeEntry);
        writeStream.write(1, &[_]u8{DIRECTORY_REGION});
    }
}
