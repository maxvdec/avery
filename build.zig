const std = @import("std");

const objects = [_][]const u8{ "kernel/init.zig", "kernel/internal/idt/idt_symbols.zig", "kernel/internal/isr/isr_symbols.zig", "kernel/internal/irq/irq_symbols.zig", "kernel/internal/gdt/gdt_symbols.zig", "kernel/internal/memory/memcopy.zig", "kernel/internal/syscalls/syscall_handler.zig" };

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{ .default_target = .{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
    } });

    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    var all_files = std.ArrayList([]const u8).init(allocator);
    try collectZigFilesRecursive(&all_files, allocator, "kernel");
    try collectZigFilesRecursive(&all_files, allocator, "fusion");

    var module_files = std.StringHashMap([]const u8).init(allocator);
    for (all_files.items) |path| {
        if (!isInArray(path, &objects)) {
            const name = std.fs.path.stem(path);
            try module_files.put(name, path);
        }
    }

    var modules = std.StringHashMap(*std.Build.Module).init(allocator);
    var it = module_files.iterator();
    while (it.next()) |entry| {
        const name = entry.key_ptr.*;
        const path = entry.value_ptr.*;
        const module = b.addModule(name, .{ .root_source_file = .{ .cwd_relative = path } });
        try modules.put(name, module);
    }

    for (objects) |obj_file| {
        const obj = b.addObject(.{
            .name = std.fs.path.stem(obj_file),
            .target = target,
            .optimize = optimize,
            .root_source_file = .{ .cwd_relative = obj_file },
        });

        obj.root_module.stack_check = false;
        obj.root_module.stack_protector = false;
        obj.root_module.link_libc = false;
        obj.root_module.strip = true;
        obj.root_module.omit_frame_pointer = true;

        var modules_copy = modules;
        var module_iter = modules.iterator();
        while (module_iter.next()) |entry| {
            const module_name = entry.key_ptr.*;
            const module = entry.value_ptr.*;
            var other_iter = modules_copy.iterator();
            while (other_iter.next()) |other_entry| {
                if (std.mem.eql(u8, module_name, other_entry.key_ptr.*)) {
                    continue;
                }
                const other_module_name = other_entry.key_ptr.*;
                const other_module = other_entry.value_ptr.*;
                module.addImport(other_module_name, other_module);
            }
            obj.root_module.addImport(module_name, module);
        }

        const art = b.addInstallArtifact(obj, .{
            .dest_dir = .{ .override = .{ .custom = "build/obj" } },
        });

        b.default_step.dependOn(&art.step);
    }
}

fn isInArray(item: []const u8, list: []const []const u8) bool {
    for (list) |e| {
        if (std.mem.eql(u8, item, e)) return true;
    }
    return false;
}

fn collectZigFilesRecursive(
    list: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    path: []const u8,
) !void {
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        const full_path = try std.fs.path.join(allocator, &.{ path, entry.name });
        switch (entry.kind) {
            .file => {
                if (std.mem.endsWith(u8, entry.name, ".zig")) {
                    try list.append(full_path);
                }
            },
            .directory => {
                try collectZigFilesRecursive(list, allocator, full_path);
            },
            else => {},
        }
    }
}
