const mem = @import("memory");
const str = @import("string");
const in = @import("input");
const out = @import("output");
const pmm = @import("physical_mem");
const vmm = @import("virtual_mem");
const multiboot2 = @import("multiboot2");
const alloc = @import("allocator");
const ata = @import("ata");

fn printMemory(memMap: multiboot2.MemoryMapTag) void {
    out.println("====== Memory Info ======");
    out.println("Memory Map:");

    var memMapCopy = memMap;
    multiboot2.printMemoryMap(&memMapCopy);
    out.println("");
    out.setTextColor(out.VgaTextColor.Cyan, out.VgaTextColor.Black);
    out.println("Device memory: ");
    const available = multiboot2.getAvailableMemory(memMap);
    out.printHex(available);
    out.println(" bytes");
    out.println("Used memory: ");
    const used = pmm.getUsedMemory();
    out.printHex(used);
    out.println(" bytes");
    out.println("Free memory: ");
    out.printHex(available - used);
    out.println(" bytes");
}

pub fn main(memMap: multiboot2.MemoryMapTag) void {
    var lastExitCode: u8 = 0;
    while (true) {
        if (lastExitCode != 0) {
            out.setTextColor(out.VgaTextColor.LightRed, out.VgaTextColor.Black);
            out.print("> ");
            out.setTextColor(out.VgaTextColor.LightGray, out.VgaTextColor.Black);
        } else {
            out.print("> ");
        }
        const command_buf = in.readln();
        const command = str.makeRuntime(command_buf);

        if (command.isEqualTo(str.make("clear"))) {
            out.clear();
            lastExitCode = 0;
        } else if (command.isEqualTo(str.make("sys.mem"))) {
            // TODO: Fix this command
            printMemory(memMap);
            lastExitCode = 0;
        } else if (command.isEqualTo(str.make("disk list"))) {
            const disks = ata.makeController();
            ata.printDeviceInfo(&disks.master);
            ata.printDeviceInfo(&disks.slave);
            lastExitCode = 0;
        } else if (command.isEqualTo(str.make("alloc"))) {
            _ = alloc.request(512).?;
            out.println("Allocated 512 bytes");
            lastExitCode = 0;
        } else {
            out.print("Command '");
            out.printstr(command);
            out.print("' not found\n");
            out.println("Make sure to check the executable is on the path");
            lastExitCode = 1;
        }
    }
}
