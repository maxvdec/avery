const out = @import("output");
const alloc = @import("allocator");
const vfs = @import("vfs");
const ata = @import("ata");
const terminal = @import("terminal");
const mem = @import("memory");
const ext = @import("extensions");

const FileDescriptor = struct {
    fd: u32 = 0,
    flags: u32 = 0,
    mode: u32 = 0,
    path: []const u8 = undefined,
};

const FLAG_READ = 0x1;
const FLAG_WRITE = 0x2;
const FLAG_APPEND = 0x4;
const FLAG_CREATE = 0x8;

const MODE_READ = 0x1;
const MODE_WRITE = 0x2;

const INVALID_FD: u64 = 0xFFFFFFFFFFFFFFFF;
const SUCCESS: u64 = 0;

var file_descriptors: [512]FileDescriptor = [_]FileDescriptor{.{}} ** 512;

extern var kernel_extensions: u32;

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
    switch (syscall_number) {
        0 => return read(arg1, arg2, arg3, arg4, arg5),
        1 => return write(arg1, arg2, arg3, arg4, arg5, extensions),
        2 => return open(arg1, arg2, arg3, arg4, arg5),
        3 => return close(arg1, arg2, arg3, arg4, arg5),
        else => return 0,
    }
}

fn write(arg1: u32, arg2: u32, arg3: u32, _: u32, _: u32, extensions: *ext.KernelExtensions) u64 {
    const ptr: [*]const u8 = @ptrFromInt(arg2);
    const len = arg3;
    const fd = arg1;

    if (fd != 1 and fd != 2) {
        for (&file_descriptors) |*file_desc| {
            if (file_desc.fd == fd) {
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

fn open(arg1: u32, arg2: u32, arg3: u32, arg4: u32, _: u32) u64 {
    const path: [*]const u8 = @ptrFromInt(arg1);
    const flags = arg3;
    const mode = arg4;

    var count: u32 = 3; // 0, 1, and 2 are reserved for stdin, stdout, and stderr
    for (&file_descriptors) |*fd| {
        if (fd.fd == 0) {
            fd.fd = count;
            fd.flags = flags;
            fd.mode = mode;
            fd.path = path[0..arg2];
            return fd.fd;
        }
        count += 1;
    }

    return SUCCESS;
}

fn read(arg1: u32, arg2: u32, arg3: u32, _: u32, _: u32) u64 {
    const fd = arg1;
    const buf: [*]u8 = @ptrFromInt(arg2);
    const len = arg3;

    if (fd != 0 and fd != 1 and fd != 2) {
        for (&file_descriptors) |*file_desc| {
            if (file_desc.fd == fd) {
                return 0;
            }
        }
        return INVALID_FD;
    }

    _ = buf + len; // Prevent unused variable warning

    switch (fd) {
        0 => {
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

fn close(arg1: u32, _: u32, _: u32, _: u32, _: u32) u64 {
    const fd = arg1;

    if (fd == 0 or fd == 1 or fd == 2) {
        return INVALID_FD;
    }

    for (&file_descriptors) |*file_desc| {
        if (file_desc.fd == fd) {
            file_desc.fd = 0; // Mark as closed
            return SUCCESS;
        }
    }

    return INVALID_FD;
}
