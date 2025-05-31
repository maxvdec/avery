const mem = @import("memory");
const str = @import("string");
const in = @import("input");
const out = @import("output");
const pmm = @import("physical_mem");
const vmm = @import("virtual_mem");
const multiboot2 = @import("multiboot2");
const alloc = @import("allocator");
const ata = @import("ata");
const vfs = @import("vfs");
const rtc = @import("rtc");
const path = @import("path");

fn printMemory(memMap: multiboot2.MemoryMapTag) void {
    @setRuntimeSafety(false);
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

pub var ataController: ?ata.AtaController = null;
pub fn getAtaController() *ata.AtaController {
    if (ataController == null) {
        ataController = ata.makeController();
    }
    return &ataController.?;
}

pub fn main(memMap: multiboot2.MemoryMapTag) void {
    @setRuntimeSafety(false);
    var lastExitCode: u8 = 0;
    var cwd: []const u8 = "/";
    _ = getAtaController(); // Initialize ATA controller
    while (true) {
        out.print(cwd);
        if (lastExitCode != 0) {
            out.setTextColor(out.VgaTextColor.Red, out.VgaTextColor.Black);
            out.print(" > ");
            out.setTextColor(out.VgaTextColor.LightGray, out.VgaTextColor.Black);
        } else {
            out.print(" > ");
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
        } else if (command.isEqualTo(str.make("time"))) {
            const time_unix = rtc.getUnixTime();
            const time = rtc.unixToDateTime(time_unix);
            const str_time = rtc.formatDateTime(time);
            out.println(str_time);
            out.print("(");
            out.printU64(time_unix);
            out.println(")");
            lastExitCode = 0;
        } else if (command.isEqualTo(str.make("ls"))) {
            if (mem.compareBytes(u8, cwd, "/")) {
                const dir = vfs.getRootDirectory(&getAtaController().master, 0);
                vfs.printDirectory(dir);
            } else {
                const dir = vfs.getDirectory(&getAtaController().master, cwd, 0);
                vfs.printDirectory(dir);
            }
            lastExitCode = 0;
        } else if (command.startsWith(str.make("heap"))) {
            alloc.debugHeap();
            lastExitCode = 0;
        } else if (command.startsWith(str.make("cd"))) {
            const parts = command.splitChar(' ');
            if (parts.len < 2) {
                out.println("Usage: cd <directory>");
                lastExitCode = 1;
                continue;
            }
            const newDir = parts.get(1).?.data;
            if (mem.startsWith(u8, newDir, "/")) {
                cwd = newDir;
            } else if (mem.compareBytes(u8, newDir, "..")) {
                cwd = path.getParentPath(cwd);
            } else if (mem.compareBytes(u8, newDir, ".")) {} else {
                cwd = path.joinPaths(cwd, newDir);
            }
            lastExitCode = 0;
        } else if (command.startsWith(str.make("read"))) {
            const parts = command.splitChar(' ');
            const route: str.String = parts.get(1).?;
            const routeData = route.data;
            const file = vfs.readFile(&getAtaController().master, 0, routeData);
            if (file == null) {
                lastExitCode = 1;
                continue;
            }
            out.print(file.?);
            out.println("");
            lastExitCode = 0;
        } else if (command.startsWith(str.make("disk"))) {
            if (command.isEqualTo(str.make("disk list"))) {
                ata.printDeviceInfo(&getAtaController().master);
                ata.printDeviceInfo(&getAtaController().slave);
                lastExitCode = 0;
            } else if (command.isEqualTo(str.make("disk primary"))) {
                ata.printDeviceInfo(&getAtaController().master);
                lastExitCode = 0;
            } else if (command.isEqualTo(str.make("disk secondary"))) {
                ata.printDeviceInfo(&getAtaController().slave);
                lastExitCode = 0;
            } else if (command.isEqualTo(str.make("disk partitions primary"))) {
                vfs.printPartitions(&getAtaController().master);
                lastExitCode = 0;
            } else if (command.isEqualTo(str.make("disk partitions secondary"))) {
                vfs.printPartitions(&getAtaController().slave);
                lastExitCode = 0;
            } else {
                out.print("The syntax for the disk command is invalid\n");
                lastExitCode = 1;
                continue;
            }
        } else if (command.isEqualTo(str.make("alloc"))) {
            _ = alloc.request(512).?;
            out.println("Allocated 512 bytes");
            lastExitCode = 0;
        } else if (command.trim().isEqualTo(str.make(""))) {
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
