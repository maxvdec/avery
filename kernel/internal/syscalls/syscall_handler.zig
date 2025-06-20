const out = @import("output");
const alloc = @import("allocator");
const vfs = @import("vfs");
const ata = @import("ata");
const terminal = @import("terminal");
const mem = @import("memory");
const ext = @import("extensions");
const scheduler = @import("scheduler");
const proc = @import("process");
const input = @import("input");
const arf = @import("arf");
const pmm = @import("physical_mem");
const vmm = @import("virtual_mem");
const unix = @import("rtc");

const FLAG_READ = 0x1;
const FLAG_WRITE = 0x2;
const FLAG_APPEND = 0x4;
const FLAG_CREATE = 0x8;

const MODE_READ = 0x1;
const MODE_WRITE = 0x2;

const INVALID_FD: u64 = 0xFFFFFFFFFFFFFFFF;
const SUCCESS: u64 = 0;

extern var kernel_extensions: u32;

extern const AVERY_VERSION_STR: []const u8;

extern fn memcpy(dest: [*]u8, src: [*]const u8, len: usize) [*]u8;

export fn syscall_handler(
    syscall_number: u32,
    arg1: u32,
    arg2: u32,
    arg3: u32,
    arg4: u32,
    arg5: u32,
) u64 {
    @setRuntimeSafety(false);
    const extensions = @as(*ext.KernelExtensions, @ptrFromInt(kernel_extensions));
    const sch = @as(*scheduler.Scheduler, @ptrFromInt(extensions.scheduler));
    out.initOutputs();
    out.switchToSerial();
    out.print("Syscall number: ");
    out.printHex(syscall_number);
    out.print(" Arg 1: ");
    out.printHex(arg1);
    out.print(" Arg 2: ");
    out.printHex(arg2);
    out.print(" Arg 3: ");
    out.printHex(arg3);
    out.print(" Arg 4: ");
    out.printHex(arg4);
    out.print(" Arg 5: ");
    out.printHex(arg5);
    out.println("");
    const retval = switch (syscall_number) {
        0x00 => return read(arg1, arg2, arg3, arg4, arg5, extensions),
        0x01 => return write(arg1, arg2, arg3, arg4, arg5, extensions),
        0x02 => return open(arg1, arg2, arg3, arg4, arg5, extensions),
        0x03 => return close(arg1, arg2, arg3, arg4, arg5, extensions),
        0x04 => return procSyscall(arg1, arg2, arg3, arg4, arg5, extensions),
        0x05 => return exit(arg1, arg2, arg3, arg4, arg5, extensions),
        0x06 => return getpid(arg1, arg2, arg3, arg4, arg5, extensions),
        0x07 => return remove(arg1, arg2, arg3, arg4, arg5, extensions),
        0x09 => return newdir(arg1, arg2, arg3, arg4, arg5, extensions),
        0x0B => return memmap(arg1, arg2, arg3, arg4, arg5, extensions),
        0x0C => return getunix(arg1, arg2, arg3, arg4, arg5, extensions),
        0x0D => return version(arg1, arg2, arg3, arg4, arg5, extensions),
        else => return 0,
    };

    sch.schedule();
    return retval;
}

fn makeFileDescriptors(extensions: *ext.KernelExtensions) mem.Array(proc.FileDescriptor) {
    const process = @as(*proc.Process, @ptrFromInt(extensions.mainProcess));
    const file_descriptors = process.file_descriptors;
    return file_descriptors;
}

fn write(arg1: u32, arg2: u32, arg3: u32, _: u32, _: u32, extensions: *ext.KernelExtensions) u64 {
    const ptr: [*]const u8 = @ptrFromInt(arg2);
    const len = arg3;
    const fd = arg1;

    var file_descriptors = makeFileDescriptors(extensions);

    if (fd != 1 and fd != 2) {
        for (file_descriptors.iterate()) |file_desc| {
            if (file_desc.fd == fd) {
                const drive = @as(*ata.AtaDrive, @ptrFromInt(extensions.ataDrive));
                const data = ptr[0..len];

                if (!vfs.fileExists(drive, file_desc.path, 0)) {
                    const result = vfs.createFile(drive, file_desc.path, 0);
                    if (result == null) {
                        return INVALID_FD;
                    }
                }

                const result = vfs.writeToFile(drive, file_desc.path, data, 0);
                if (result == null) {
                    return INVALID_FD;
                }

                return 0;
            }
        }
        return INVALID_FD;
    }

    switch (fd) {
        1 => {
            if (extensions.framebufferTerminal != 0) {
                const term = @as(*terminal.FramebufferTerminal, @ptrFromInt(extensions.framebufferTerminal));
                term.putString(ptr[0..len]);
            } else {
                out.switchToSerial();
                out.print(ptr[0..len]);
            }
        },
        else => return INVALID_FD,
    }
    return SUCCESS;
}

fn open(arg1: u32, arg2: u32, arg3: u32, _: u32, _: u32, extensions: *ext.KernelExtensions) u64 {
    const path: [*]const u8 = @ptrFromInt(arg1);
    const flags = arg2;
    const mode = arg3;

    var file_descriptors = makeFileDescriptors(extensions);

    const id = file_descriptors.len + 1;

    const null_byte = mem.findPtr(u8, path, 0x00);

    const file_desc = proc.FileDescriptor{
        .fd = id,
        .path = path[0..null_byte],
        .flags = flags,
        .mode = mode,
    };

    for (file_descriptors.iterate()) |*fd| {
        if (fd.fd == 0) {
            fd.* = file_desc;
            return SUCCESS;
        }
    }

    file_descriptors.append(file_desc);

    return SUCCESS;
}

fn read(arg1: u32, arg2: u32, arg3: u32, _: u32, _: u32, extensions: *ext.KernelExtensions) u64 {
    const fd = arg1;
    const buf: [*]u8 = @ptrFromInt(arg2);
    const len = arg3;

    var file_descriptors = makeFileDescriptors(extensions);

    if (fd != 1 and fd != 2) {
        for (file_descriptors.iterate()) |file_desc| {
            if (file_desc.fd == fd) {
                const drive = @as(*ata.AtaDrive, @ptrFromInt(extensions.ataDrive));

                if (!vfs.fileExists(drive, file_desc.path, 0)) {
                    return INVALID_FD;
                }

                const result = vfs.readFile(drive, 0, file_desc.path);
                if (result == null) {
                    return INVALID_FD;
                }

                _ = memcpy(buf, result.?.ptr, len);
                return len;
            }
        }
        return INVALID_FD;
    }

    switch (fd) {
        0 => {
            const framebuffer_terminal = @as(*terminal.FramebufferTerminal, @ptrFromInt(extensions.framebufferTerminal));
            out.switchToGraphics(framebuffer_terminal);
            const data = input.readbytes(len);
            _ = memcpy(buf, data.ptr, len);
            return SUCCESS; // Simulate reading from stdin
        },
        1 => {
            return INVALID_FD;
        },
        2 => {
            return INVALID_FD;
        },
        else => {
            return INVALID_FD; // Invalid file descriptor
        },
    }
}

fn close(arg1: u32, _: u32, _: u32, _: u32, _: u32, extensions: *ext.KernelExtensions) u64 {
    const fd = arg1;

    if (fd == 0 or fd == 1 or fd == 2) {
        return INVALID_FD;
    }

    const file_descriptors = makeFileDescriptors(extensions);

    for (file_descriptors.iterate()) |*file_desc| {
        if (file_desc.fd == fd) {
            file_desc.fd = 0; // Mark as closed
            return SUCCESS;
        }
    }

    return INVALID_FD;
}

fn getpid(_: u32, _: u32, _: u32, _: u32, _: u32, extensions: *ext.KernelExtensions) u64 {
    const process = @as(*proc.Process, @ptrFromInt(extensions.mainProcess));
    return process.pid;
}

fn procSyscall(arg1: u32, _: u32, _: u32, _: u32, _: u32, extensions: *ext.KernelExtensions) u64 {
    scheduler.scheduler = @ptrFromInt(extensions.scheduler);

    const buf: [*]const u8 = @ptrFromInt(arg1);
    const bufEnd = mem.findPtr(u8, buf, 0x0);
    const data = buf[0..bufEnd];

    const drive = @as(*ata.AtaDrive, @ptrFromInt(extensions.ataDrive));

    if (!vfs.fileExists(drive, data, 0)) {
        return INVALID_FD;
    }

    const file = vfs.readFile(drive, 0, data);

    if (file == null) {
        return INVALID_FD;
    }

    const exec = arf.loadExecutable(file.?);
    const process = arf.createProcess(exec, drive, .Normal);

    if (process == null) {
        return INVALID_FD;
    }

    return process.?.pid;
}

fn exit(arg1: u32, _: u32, _: u32, _: u32, _: u32, extensions: *ext.KernelExtensions) u64 {
    const process = @as(*proc.Process, @ptrFromInt(extensions.mainProcess));
    process.terminate();
    return arg1;
}

fn remove(arg1: u32, _: u32, _: u32, _: u32, _: u32, extensions: *ext.KernelExtensions) u64 {
    const drive = @as(*ata.AtaDrive, @ptrFromInt(extensions.ataDrive));
    const pathData: [*]u8 = @ptrFromInt(arg1);
    const pathEnd = mem.findPtr(u8, pathData, 0x0);
    const path = pathData[0..pathEnd];

    if (!vfs.fileExists(drive, path, 0)) {
        return INVALID_FD;
    }

    const result = vfs.deleteFile(drive, path, 0);
    if (result == null) {
        return INVALID_FD;
    }

    return SUCCESS;
}

fn newdir(arg1: u32, _: u32, _: u32, _: u32, _: u32, extensions: *ext.KernelExtensions) u64 {
    const drive = @as(*ata.AtaDrive, @ptrFromInt(extensions.ataDrive));
    const pathData: [*]u8 = @ptrFromInt(arg1);
    const pathEnd = mem.findPtr(u8, pathData, 0x0);
    const path = pathData[0..pathEnd];

    const result = vfs.makeNewDirectory(drive, path, 0);
    if (result == null) {
        return INVALID_FD;
    }

    return SUCCESS;
}

fn memmap(arg1: u32, arg2: u32, arg3: u32, arg4: u32, arg5: u32, extensions: *ext.KernelExtensions) u64 {
    @setRuntimeSafety(false);

    const addr = arg1;
    const length = arg2;
    const prot = arg3;
    _ = arg4;
    const fd = arg5;

    if (length == 0) {
        return INVALID_FD;
    }

    const page_size = pmm.PAGE_SIZE;
    const pages_needed = (length + page_size - 1) / page_size;

    var vmm_flags: u32 = vmm.PAGE_PRESENT;

    if ((prot & MODE_WRITE) != 0) {
        vmm_flags |= vmm.PAGE_RW;
    }

    vmm_flags |= vmm.PAGE_USER;

    var virt_addr: usize = 0;

    if (addr == 0) {
        const allocated_addr = vmm.allocVirtual(length, vmm_flags);
        if (allocated_addr == null) {
            return INVALID_FD;
        }
        virt_addr = allocated_addr.?;
    } else {
        virt_addr = addr;

        var i: usize = 0;
        while (i < pages_needed) : (i += 1) {
            const phys = pmm.allocPage();
            if (phys == null) {
                var j: usize = 0;
                while (j < i) : (j += 1) {
                    const cleanup_virt = virt_addr + j * page_size;
                    const cleanup_phys = vmm.translate(cleanup_virt);
                    if (cleanup_phys) |p| {
                        pmm.freePage(p);
                    }
                    vmm.unmapPage(cleanup_virt);
                }
                return INVALID_FD;
            }

            vmm.mapPage(virt_addr + i * page_size, phys.?, vmm_flags);
        }
    }

    if (fd != 0xFFFFFFFF) { // fd != -1 (not anonymous mapping)
        const file_descriptors = makeFileDescriptors(extensions);

        var found_fd = false;
        for (file_descriptors.iterate()) |file_desc| {
            if (file_desc.fd == fd) {
                found_fd = true;

                const drive = @as(*ata.AtaDrive, @ptrFromInt(extensions.ataDrive));

                if (!vfs.fileExists(drive, file_desc.path, 0)) {
                    vmm.freeVirtual(virt_addr, length);
                    return INVALID_FD;
                }

                const file_data = vfs.readFile(drive, 0, file_desc.path);
                if (file_data == null) {
                    vmm.freeVirtual(virt_addr, length);
                    return INVALID_FD;
                }

                const dest_ptr: [*]u8 = @ptrFromInt(virt_addr);
                const file_size = @min(file_data.?.len, length);
                _ = memcpy(dest_ptr, file_data.?.ptr, file_size);

                if (length > file_size) {
                    const remaining_ptr = dest_ptr + file_size;
                    const remaining_size = length - file_size;
                    for (0..remaining_size) |i| {
                        remaining_ptr[i] = 0;
                    }
                }

                break;
            }
        }

        if (!found_fd) {
            vmm.freeVirtual(virt_addr, length);
            return INVALID_FD;
        }
    } else {
        const dest_ptr: [*]u8 = @ptrFromInt(virt_addr);
        for (0..length) |i| {
            dest_ptr[i] = 0;
        }
    }

    return virt_addr;
}

fn getunix(_: u32, _: u32, _: u32, _: u32, _: u32, _: *ext.KernelExtensions) u64 {
    return unix.getUnixTime();
}

fn version(arg1: u32, arg2: u32, _: u32, _: u32, _: u32, _: *ext.KernelExtensions) u64 {
    const buf: [*]u8 = @ptrFromInt(arg1);
    const len = arg2;

    mem.copySafe(AVERY_VERSION_STR, buf, len);

    return 0;
}
