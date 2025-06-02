const vfs = @import("vfs");
const out = @import("output");
const str = @import("string");
const sys = @import("system");
const ata = @import("ata");
const alloc = @import("allocator");
const mem = @import("memory");
const path = @import("path");
const rtc = @import("rtc");
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
    while (currentRegion >= drive.partitions[partition].start_sector and currentRegion < drive.partitions[partition].start_sector + drive.partitions[partition].size) {
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

    while (true) {
        const bufferData = ata.readSectors(drive, currentRegion, 1);

        var offset: usize = 1;

        while (offset < 508) {
            if (offset >= bufferData.len) break;

            const entryType = bufferData[offset];
            offset += 1;

            if (entryType == EMPTY_REGION or entryType == DELETED_REGION) {
                if (offset - 1 + sizeAtLeast <= 508) {
                    return @intCast(currentRegion * 512 + (offset - 1));
                } else {
                    break;
                }
            }

            offset += 24;
            if (offset >= 508) break;

            while (offset < 508 and bufferData[offset] != 0) {
                offset += 1;
            }
            if (offset >= 508) break;

            offset += 1;
            if (offset + 4 > 508) break;

            offset += 4;
        }

        if (offset >= 508) {
            var continueRegion: u32 = 0;
            continueRegion |= @as(u32, bufferData[508]);
            continueRegion |= @as(u32, bufferData[509]) << 8;
            continueRegion |= @as(u32, bufferData[510]) << 16;
            continueRegion |= @as(u32, bufferData[511]) << 24;

            if (continueRegion == 0) {
                const nextRegion = findFreeRegion(drive, 0, &[_]u32{});
                if (nextRegion == 0) {
                    out.println("No free region found.");
                    return 0;
                }

                var sectorData = ata.readSectors(drive, currentRegion, 1);
                sectorData[508] = @as(u8, @intCast(nextRegion & 0xFF));
                sectorData[509] = @as(u8, @intCast((nextRegion >> 8) & 0xFF));
                sectorData[510] = @as(u8, @intCast((nextRegion >> 16) & 0xFF));
                sectorData[511] = @as(u8, @intCast((nextRegion >> 24) & 0xFF));
                ata.writeSectors(drive, currentRegion, 1, &sectorData);

                var newSector = [_]u8{0} ** 512;
                newSector[0] = DIRECTORY_REGION;
                ata.writeSectors(drive, nextRegion, 1, &newSector);

                return @intCast(nextRegion * 512 + 1);
            } else {
                currentRegion = continueRegion;
                continue;
            }
        }

        break;
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
    if (parentRegion == 0) {
        out.print("Parent directory not found: ");
        out.println(withoutLastComponent);
        return;
    } else {
        const size = 1 + 24 + directoryName.len + 1 + 4;
        const freeEntry = findFreeDirectoryEntry(drive, parentRegion, size);
        if (freeEntry == 0) {
            out.println("No free directory entry found.");
            return;
        }

        const entrySector = freeEntry / 512;
        const entryOffset = freeEntry % 512;

        var sectorBuffer = ata.readSectors(drive, @intCast(entrySector), 1);

        var bufferOffset: usize = @intCast(entryOffset);

        sectorBuffer[bufferOffset] = DIRECTORY_REGION;
        bufferOffset += 1;

        const currentTime = rtc.getUnixTime();
        const timeBytes = mem.reinterpretToBytes(u64, currentTime);

        @memcpy(sectorBuffer[bufferOffset .. bufferOffset + 8], timeBytes[0..8]);
        bufferOffset += 8;

        @memcpy(sectorBuffer[bufferOffset .. bufferOffset + 8], timeBytes[0..8]);
        bufferOffset += 8;

        @memcpy(sectorBuffer[bufferOffset .. bufferOffset + 8], timeBytes[0..8]);
        bufferOffset += 8;

        @memcpy(sectorBuffer[bufferOffset .. bufferOffset + directoryName.len], directoryName);
        bufferOffset += directoryName.len;

        sectorBuffer[bufferOffset] = 0;
        bufferOffset += 1;

        const regionNumber = findFreeRegion(drive, partition, &[_]u32{});
        if (regionNumber == 0) {
            out.println("No free region found for new directory.");
            return;
        }

        const regionBytes = mem.reinterpretToBytes(u32, regionNumber);
        @memcpy(sectorBuffer[bufferOffset .. bufferOffset + 4], regionBytes[0..4]);

        ata.writeSectors(drive, @intCast(entrySector), 1, &sectorBuffer);

        var newSector: [512]u8 = [_]u8{0} ** 512;
        var newSectorOffset: usize = 0;

        newSector[newSectorOffset] = DIRECTORY_REGION;
        newSectorOffset += 1;

        newSector[newSectorOffset] = DIRECTORY_REGION;
        newSectorOffset += 1;

        @memcpy(newSector[newSectorOffset .. newSectorOffset + 8], timeBytes[0..8]); // Last accessed
        newSectorOffset += 8;
        @memcpy(newSector[newSectorOffset .. newSectorOffset + 8], timeBytes[0..8]); // Last modified
        newSectorOffset += 8;
        @memcpy(newSector[newSectorOffset .. newSectorOffset + 8], timeBytes[0..8]); // Created
        newSectorOffset += 8;

        newSector[newSectorOffset] = '.';
        newSectorOffset += 1;

        newSector[newSectorOffset] = 0;
        newSectorOffset += 1;

        @memcpy(newSector[newSectorOffset .. newSectorOffset + 4], regionBytes[0..4]);

        ata.writeSectors(drive, regionNumber, 1, &newSector);

        return;
    }
}

pub fn createFile(drive: *ata.AtaDrive, fileName: []const u8, partition: u32) void {
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
    var fileNameOnly: []const u8 = "";
    const lastSlashIndex = mem.findLast(u8, fileName, '/');
    if (lastSlashIndex == null) {
        withoutLastComponent = "";
        fileNameOnly = fileName;
    } else {
        withoutLastComponent = fileName[0..lastSlashIndex.?];
        fileNameOnly = fileName[lastSlashIndex.? + 1 ..];
    }

    const parentRegion = traverseDirectory(drive, withoutLastComponent, partition);
    if (parentRegion == 0) {
        out.print("Parent directory not found: ");
        out.println(withoutLastComponent);
        return;
    }

    const size = 1 + 24 + fileNameOnly.len + 1 + 4;
    const freeEntry = findFreeDirectoryEntry(drive, parentRegion, size);

    if (freeEntry == 0) {
        out.println("No free directory entry found.");
        return;
    }

    const entrySector = freeEntry / 512;
    const entryOffset = freeEntry % 512;

    var sectorBuffer = ata.readSectors(drive, @intCast(entrySector), 1);

    var bufferOffset: usize = @intCast(entryOffset);

    sectorBuffer[bufferOffset] = FILE_REGION;
    bufferOffset += 1;

    const currentTime = rtc.getUnixTime();
    const timeBytes = mem.reinterpretToBytes(u64, currentTime);

    @memcpy(sectorBuffer[bufferOffset .. bufferOffset + 8], timeBytes[0..8]);
    bufferOffset += 8;

    @memcpy(sectorBuffer[bufferOffset .. bufferOffset + 8], timeBytes[0..8]);
    bufferOffset += 8;

    @memcpy(sectorBuffer[bufferOffset .. bufferOffset + 8], timeBytes[0..8]);
    bufferOffset += 8;

    @memcpy(sectorBuffer[bufferOffset .. bufferOffset + fileNameOnly.len], fileNameOnly);
    bufferOffset += fileNameOnly.len;

    sectorBuffer[bufferOffset] = 0;
    bufferOffset += 1;

    const regionNumber = findFreeRegion(drive, partition, &[_]u32{});
    if (regionNumber == 0) {
        out.println("No free region found for new file.");
        return;
    }

    const regionBytes = mem.reinterpretToBytes(u32, regionNumber);
    @memcpy(sectorBuffer[bufferOffset .. bufferOffset + 4], regionBytes[0..4]);

    ata.writeSectors(drive, @intCast(entrySector), 1, &sectorBuffer);

    var newSector: [512]u8 = [_]u8{0} ** 512;

    newSector[0] = FILE_REGION;

    newSector[508] = 0;
    newSector[509] = 0;
    newSector[510] = 0;
    newSector[511] = 0;

    ata.writeSectors(drive, regionNumber, 1, &newSector);
}

pub fn writeToFile(drive: *ata.AtaDrive, fileName: []const u8, contents: []const u8, partition: u32) void {
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
    var fileNameOnly: []const u8 = "";
    const lastSlashIndex = mem.findLast(u8, fileName, '/');
    if (lastSlashIndex == null) {
        withoutLastComponent = "";
        fileNameOnly = fileName;
    } else {
        withoutLastComponent = fileName[0..lastSlashIndex.?];
        fileNameOnly = fileName[lastSlashIndex.? + 1 ..];
    }

    const parentRegion = traverseDirectory(drive, withoutLastComponent, partition);
    if (parentRegion == 0) {
        return;
    }

    const fileRegion = findFileInDirectory(drive, fileNameOnly, parentRegion);
    var currentRegion: u32 = 0;

    if (fileRegion == 0) {
        createFile(drive, fileName, partition);

        const newFileRegion = findFileInDirectory(drive, fileNameOnly, parentRegion);
        if (newFileRegion == 0) {
            out.println("Failed to create file.");
            return;
        }
        currentRegion = newFileRegion;
    } else {
        currentRegion = fileRegion;
        clearFileData(drive, currentRegion);
    }

    var bytesWritten: usize = 0;
    var usedRegions = mem.Array(u32).init();

    usedRegions.append(currentRegion);

    while (bytesWritten < contents.len) {
        const maxDataPerRegion = 512 - 5;
        const remainingBytes = contents.len - bytesWritten;
        const bytesToWrite = if (remainingBytes > maxDataPerRegion) maxDataPerRegion else remainingBytes;

        var sectorBuffer: [512]u8 = [_]u8{0} ** 512;

        sectorBuffer[0] = FILE_REGION;

        @memcpy(sectorBuffer[1 .. 1 + bytesToWrite], contents[bytesWritten .. bytesWritten + bytesToWrite]);
        bytesWritten += bytesToWrite;

        if (bytesWritten < contents.len) {
            const nextRegion = findFreeRegion(drive, partition, usedRegions.coerce());
            if (nextRegion == 0) {
                out.println("No free region found for file continuation.");
                return;
            }

            usedRegions.append(nextRegion);

            const nextRegionBytes = mem.reinterpretToBytes(u32, nextRegion);
            sectorBuffer[508] = nextRegionBytes[3];
            sectorBuffer[509] = nextRegionBytes[2];
            sectorBuffer[510] = nextRegionBytes[1];
            sectorBuffer[511] = nextRegionBytes[0];
        } else {
            sectorBuffer[508] = 0;
            sectorBuffer[509] = 0;
            sectorBuffer[510] = 0;
            sectorBuffer[511] = 0;
        }

        ata.writeSectors(drive, currentRegion, 1, &sectorBuffer);

        if (bytesWritten < contents.len) {
            currentRegion = (@as(u32, sectorBuffer[508]) << 24) |
                (@as(u32, sectorBuffer[509]) << 16) |
                (@as(u32, sectorBuffer[510]) << 8) |
                (@as(u32, sectorBuffer[511]));
        }
    }

    updateFileTimestamp(drive, parentRegion, fileNameOnly);
}

fn clearFileData(drive: *ata.AtaDrive, firstRegion: u32) void {
    var currentRegion = firstRegion;

    while (currentRegion != 0) {
        var sectorBuffer = ata.readSectors(drive, currentRegion, 1);

        const nextBytes = sectorBuffer[508..512];
        const nextRegion = (@as(u32, nextBytes[0]) << 24) |
            (@as(u32, nextBytes[1]) << 16) |
            (@as(u32, nextBytes[2]) << 8) |
            (@as(u32, nextBytes[3]));

        if (currentRegion != firstRegion) {
            var emptySector: [512]u8 = [_]u8{0} ** 512;
            emptySector[0] = EMPTY_REGION;
            ata.writeSectors(drive, currentRegion, 1, &emptySector);
        }

        currentRegion = nextRegion;
    }
}

fn updateFileTimestamp(drive: *ata.AtaDrive, directoryRegion: u32, fileName: []const u8) void {
    var currentRegion = directoryRegion;

    while (currentRegion != 0) {
        var sectorBuffer = ata.readSectors(drive, currentRegion, 1);

        if (sectorBuffer[0] != DIRECTORY_REGION) {
            break;
        }

        var offset: usize = 1;
        var modified = false;

        while (offset < 508) {
            if (sectorBuffer[offset] == 0x00) {
                break;
            }

            if (sectorBuffer[offset] == EMPTY_REGION or sectorBuffer[offset] == DELETED_REGION) {
                offset += 1;
                offset += 24;
                while (offset < 508 and sectorBuffer[offset] != 0) {
                    offset += 1;
                }
                if (offset < 508) offset += 1;
                offset += 4;
                continue;
            }

            const entryType = sectorBuffer[offset];
            offset += 1;

            const timestampOffset = offset;
            offset += 24;

            const nameStart = offset;
            while (offset < 508 and sectorBuffer[offset] != 0) {
                offset += 1;
            }

            if (offset >= 508) break;

            const entryFileName = sectorBuffer[nameStart..offset];
            offset += 1;
            offset += 4;

            if (entryType == FILE_REGION and mem.compareBytes(u8, entryFileName, fileName)) {
                const currentTime = rtc.getUnixTime();
                const timeBytes = mem.reinterpretToBytes(u64, currentTime);

                @memcpy(sectorBuffer[timestampOffset .. timestampOffset + 8], timeBytes[0..8]);
                @memcpy(sectorBuffer[timestampOffset + 8 .. timestampOffset + 16], timeBytes[0..8]);

                modified = true;
                break;
            }
        }

        if (modified) {
            ata.writeSectors(drive, currentRegion, 1, &sectorBuffer);
            break;
        }

        const nextBytes = sectorBuffer[508..512];
        currentRegion = (@as(u32, nextBytes[0]) << 24) |
            (@as(u32, nextBytes[1]) << 16) |
            (@as(u32, nextBytes[2]) << 8) |
            (@as(u32, nextBytes[3]));
    }
}

pub fn fileExists(drive: *ata.AtaDrive, fileName: []const u8, partition: u32) bool {
    @setRuntimeSafety(false);
    if (!drive.is_present) {
        out.println("No drive detected.");
        return false;
    }

    const partition_data = detectPartitions(drive);
    if (partition >= partition_data.len) {
        return false;
    }
    if (!partition_data[partition].exists) {
        return false;
    }

    var withoutLastComponent: []const u8 = "";
    var fileNameOnly: []const u8 = "";
    const lastSlashIndex = mem.findLast(u8, fileName, '/');
    if (lastSlashIndex == null) {
        withoutLastComponent = "";
        fileNameOnly = fileName;
    } else {
        withoutLastComponent = fileName[0..lastSlashIndex.?];
        fileNameOnly = fileName[lastSlashIndex.? + 1 ..];
    }

    const parentRegion = traverseDirectory(drive, withoutLastComponent, partition);
    if (parentRegion == 0) {
        return false;
    }

    const fileRegion = findFileInDirectory(drive, fileNameOnly, parentRegion);
    return fileRegion != 0;
}

pub fn directoryExists(drive: *ata.AtaDrive, dirName: []const u8, partition: u32) bool {
    @setRuntimeSafety(false);
    if (!drive.is_present) {
        out.println("No drive detected.");
        return false;
    }

    const partition_data = detectPartitions(drive);
    if (partition >= partition_data.len) {
        return false;
    }
    if (!partition_data[partition].exists) {
        return false;
    }

    var withoutLastComponent: []const u8 = "";
    var dirNameOnly: []const u8 = "";
    const lastSlashIndex = mem.findLast(u8, dirName, '/');
    if (lastSlashIndex == null) {
        withoutLastComponent = "";
        dirNameOnly = dirName;
    } else {
        withoutLastComponent = dirName[0..lastSlashIndex.?];
        dirNameOnly = dirName[lastSlashIndex.? + 1 ..];
    }

    const parentRegion = traverseDirectory(drive, withoutLastComponent, partition);
    if (parentRegion == 0) {
        return false;
    }

    const entries = parseDirectory(drive, parentRegion, ".");
    for (entries.entries) |entry| {
        if (mem.compareBytes(u8, entry.name, dirNameOnly) and entry.isDirectory) {
            return true;
        }
    }

    return false;
}
