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

    var cwd_buffer: [256]u8 = undefined;
    cwd_buffer[0] = '/';
    cwd_buffer[1] = 0;
    var cwd_len: usize = 1;

    _ = getAtaController();

    while (true) {
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
        } else if (command.startsWith(str.make("new"))) {
            const parts = command.splitChar(' ');
            if (parts.len < 2) {
                out.println("Usage: new <file>");
                lastExitCode = 1;
                continue;
            }

            const fileName = parts.get(1).?;

            if (fileName.startsWith(str.make("/"))) {
                _ = vfs.createFile(&getAtaController().master, fileName.data, 0);
                lastExitCode = 0;
            } else {
                const joinedPath = path.joinPaths(cwd, fileName.data);
                _ = vfs.createFile(&getAtaController().master, joinedPath, 0);
                lastExitCode = 0;
            }
        } else if (command.startsWith(str.make("write"))) {
            const parts = command.splitChar(' ');
            if (parts.len < 3) {
                out.println("Usage: write <filename> <content>");
                lastExitCode = 1;
                continue;
            }

            const fileName = parts.get(1).?;
            const contents = parts.getRest(2).?;
            const content = contents.joinIntoString(" ");

            var content_buffer: [1024]u8 = undefined;
            const content_len = safeCopyString(content_buffer[0..], content.data);
            const content_slice = content_buffer[0..content_len];

            if (fileName.startsWith(str.make("/"))) {
                _ = vfs.writeToFile(&getAtaController().master, fileName.data, content_slice, 0);
                lastExitCode = 0;
            } else {
                const joinedPath = path.joinPaths(cwd, fileName.data);
                _ = vfs.writeToFile(&getAtaController().master, joinedPath, content_slice, 0);
                lastExitCode = 0;
            }
        } else if (command.startsWith(str.make("mkdir"))) {
            const parts = command.splitChar(' ');
            if (parts.len < 2) {
                out.println("Usage: mkdir <directory>");
                lastExitCode = 1;
                return;
            }

            const newDirStr = parts.get(1).?;
            if (newDirStr.startsWith(str.make("/"))) {
                const dir = vfs.makeNewDirectory(&getAtaController().master, newDirStr.data, 0);
                if (dir == null) {
                    lastExitCode = 1;
                } else {
                    lastExitCode = 0;
                }
            } else {
                const joinedPath = path.joinPaths(cwd, newDirStr.data);
                const dir = vfs.makeNewDirectory(&getAtaController().master, joinedPath, 0);
                if (dir == null) {
                    lastExitCode = 1;
                } else {
                    lastExitCode = 0;
                }
            }
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
                const parentPath = path.getParentPath(cwd);
                const parentLen = parentPath.len;
                if (parentLen < 256) {
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
            var printHex: bool = false;
            if (parts.len < 2) {
                out.println("Usage: read <filename>");
                lastExitCode = 1;
                continue;
            } else if (parts.len == 3) {
                if (parts.get(1).?.isEqualTo(str.make("-h"))) {
                    printHex = true;
                } else {
                    out.println("Usage: read <filename> [-h]");
                    lastExitCode = 1;
                    continue;
                }
            }

            const fileName = parts.get(if (printHex) 2 else 1).?;

            if (fileName.startsWith(str.make("/"))) {
                var route_buffer: [256]u8 = undefined;
                const route_len = @min(fileName.length(), 255);
                var i: usize = 0;
                while (i < route_len) : (i += 1) {
                    route_buffer[i] = fileName.data[i];
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
            } else {
                const joinedPath = path.joinPaths(cwd, fileName.data);

                var route_buffer: [256]u8 = undefined;
                const route_len = @min(joinedPath.len, 255);
                var i: usize = 0;
                while (i < route_len) : (i += 1) {
                    route_buffer[i] = joinedPath[i];
                }
                route_buffer[route_len] = 0;
                const routeData = route_buffer[0..route_len];

                const file = vfs.readFile(&getAtaController().master, 0, routeData);
                if (file == null) {
                    lastExitCode = 1;
                    continue;
                }
                if (printHex) {
                    for (file.?) |byte| {
                        out.printHex(byte);
                        out.print(" ");
                    }
                    out.println("");
                } else {
                    out.print(file.?);
                    out.println("");
                }
                lastExitCode = 0;
            }
        } else if (command.startsWith(str.make("exec"))) {
            const fileName = command.splitChar(' ').get(1) orelse {
                out.println("Usage: exec <filename>");
                lastExitCode = 1;
                continue;
            };

            if (fileName.startsWith(str.make("/"))) {
                var route_buffer: [256]u8 = undefined;
                const route_len = @min(fileName.length(), 255);
                var i: usize = 0;
                while (i < route_len) : (i += 1) {
                    route_buffer[i] = fileName.data[i];
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
            } else {
                const joinedPath = path.joinPaths(cwd, fileName.data);

                var route_buffer: [256]u8 = undefined;
                const route_len = @min(joinedPath.len, 255);
                var i: usize = 0;
                while (i < route_len) : (i += 1) {
                    route_buffer[i] = joinedPath[i];
                }
                route_buffer[route_len] = 0;
                const routeData = route_buffer[0..route_len];

                const file = vfs.readFile(&getAtaController().master, 0, routeData);
                if (file == null) {
                    lastExitCode = 1;
                    continue;
                }
                // if (proc == null) {
                //     out.println("Failed to load ELF file");
                //     lastExitCode = 1;
                //     continue;
                // }
                // proc.?.run();

                lastExitCode = 0;
            }
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
