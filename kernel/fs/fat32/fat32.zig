const ata = @import("ata");
const mem = @import("memory");
const alloc = @import("allocator");
const out = @import("output");

const PartitionTableEntry = packed struct {
    bootable: u8,
    chsBegin0: u8,
    chsBegin1: u8,
    chsBegin2: u8,
    typeCode: u8,
    chsEnd0: u8,
    chsEnd1: u8,
    chsEnd2: u8,
    lbaBegin: u32,
    size: u32,
};

const MasterBootRecord = struct {
    bootCode: [446]u8,
    partitionTable: [4]PartitionTableEntry,
    signature: u16,

    pub fn debugPrint(self: *const MasterBootRecord) void {
        out.println("Device Boot Record:");
        out.print("Signature is: ");
        out.printHex(self.signature);
        out.print("\n");
    }
};

extern fn memcpy(dst: [*]u8, src: [*]u8, count: usize) [*]u8;

pub fn readMBR(drive: *const ata.AtaDrive) MasterBootRecord {
    const buffer: [*]u8 = alloc.request(512).?;
    ata.readSectors(drive, 0, 1, buffer);

    var partitions: [4]PartitionTableEntry = undefined;
    for (0..4) |i| {
        const offset = 446 + i * @sizeOf(PartitionTableEntry);
        partitions[i] = mem.reinterpretBytes(PartitionTableEntry, buffer[offset .. offset + @sizeOf(PartitionTableEntry)], true).unwrap();
    }

    var bootCode: [446]u8 = undefined;
    @memcpy(&bootCode, buffer[0..446]);
    const signature: u16 = mem.reinterpretBytes(u16, buffer[510..512], true).unwrap();
    const mbr = MasterBootRecord{
        .bootCode = bootCode,
        .partitionTable = partitions,
        .signature = signature,
    };

    mbr.debugPrint();
    return mbr;
}
