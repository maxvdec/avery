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

const FLAG_READ = 0x1;
const FLAG_WRITE = 0x2;
const FLAG_APPEND = 0x4;
const FLAG_CREATE = 0x8;

const MODE_READ = 0x1;
const MODE_WRITE = 0x2;

const INVALID_FD: u64 = 0xFFFFFFFFFFFFFFFF;
const SUCCESS: u64 = 0;

extern var kernel_extensions: u32;

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
        0 => return read(arg1, arg2, arg3, arg4, arg5, extensions),
        1 => return write(arg1, arg2, arg3, arg4, arg5, extensions),
        2 => return open(arg1, arg2, arg3, arg4, arg5, extensions),
        3 => return close(arg1, arg2, arg3, arg4, arg5, extensions),
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
