const vfs = @import("vfs");
const out = @import("output");
const str = @import("string");
const sys = @import("system");
const ata = @import("ata");
const alloc = @import("allocator");
const mem = @import("memory");
extern fn memcpy(dest: [*]u8, src: [*]const u8, len: usize) [*]u8;

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
