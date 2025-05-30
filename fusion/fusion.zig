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

    // Use a fixed buffer for cwd to avoid corruption
    var cwd_buffer: [256]u8 = undefined;
    cwd_buffer[0] = '/';
    cwd_buffer[1] = 0;
    var cwd_len: usize = 1;

    _ = getAtaController(); // Initialize ATA controller

    while (true) {
        // Create current working directory string safely
        const cwd = cwd_buffer[0..cwd_len];

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
            printMemory(memMap);
            lastExitCode = 0;
        } else if (command.isEqualTo(str.make("sys.stack"))) {
            mem.printStack();
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
            if (cwd_len == 1 and cwd_buffer[0] == '/') {
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

            const newDirStr = parts.get(1).?;
            const newDir = newDirStr.data;

            if (newDir.len > 0 and newDir[0] == '/') {
                cwd_buffer[0] = '/';
                cwd_buffer[1] = 0;
                cwd_len = 1;
            } else if (mem.compareBytes(u8, newDir, "..")) {
                // Parent directory
                const parentPath = path.getParentPath(cwd);
                const parentLen = parentPath.len;
                if (parentLen < 256) {
                    // Copy parent path safely
                    var i: usize = 0;
                    while (i < parentLen) : (i += 1) {
                        cwd_buffer[i] = parentPath[i];
                    }
                    cwd_buffer[parentLen] = 0;
                    cwd_len = parentLen;
                }
            } else if (mem.compareBytes(u8, newDir, ".")) {} else {
                const joinedPath = path.joinPaths(cwd, newDir);
                const joinedLen = joinedPath.len;
                if (joinedLen < 256) {
                    // Copy joined path safely
                    var i: usize = 0;
                    while (i < joinedLen) : (i += 1) {
                        cwd_buffer[i] = joinedPath[i];
                    }
                    cwd_buffer[joinedLen] = 0;
                    cwd_len = joinedLen;
                } else {
                    out.println("Path too long!");
                    lastExitCode = 1;
                    continue;
                }
            }
            lastExitCode = 0;
        } else if (command.startsWith(str.make("read"))) {
            const parts = command.splitChar(' ');
            if (parts.len < 2) {
                out.println("Usage: read <filename>");
                lastExitCode = 1;
                continue;
            }

            const route = parts.get(1).?;

            var route_buffer: [256]u8 = undefined;
            const route_len = @min(route.length(), 255);
            var i: usize = 0;
            while (i < route_len) : (i += 1) {
                route_buffer[i] = route.data[i];
            }
            route_buffer[route_len] = 0;

            const routeData = route_buffer[0..route_len];
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

fn safeCopyString(dest: []u8, src: []const u8) usize {
    const copy_len = @min(dest.len - 1, src.len);
    var i: usize = 0;
    while (i < copy_len) : (i += 1) {
        dest[i] = src[i];
    }
    dest[copy_len] = 0;
    return copy_len;
}
