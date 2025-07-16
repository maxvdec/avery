const arf = @import("arf");
const driver = @import("drv_load");
const kalloc = @import("kern_allocator");
const mem = @import("memory");
const out = @import("output");
const sys = @import("system");
const drv_type = @import("drv_types");

pub const RawDriver = struct { typ: driver.DriverType, drv: driver.Driver, exec: *arf.Executable };

pub const DriverFunction = struct {
    name: []const u8,
    addr: usize,
};

pub const LoadedDriver = struct {
    typ: driver.DriverType,
    drv: driver.Driver,
    functions: mem.Array(DriverFunction),
    base_addr: usize,
    is_loaded: bool,
    finalDrv: ?drv_type.Driver,
};

pub const NativeFunction = struct {
    name: []const u8,
    addr: usize,
};

const WANTED_FUNCTIONS = &[_][]const u8{ "init", "destroy" };

pub fn makeRawDriver(drv: driver.Driver) *RawDriver {
    @setRuntimeSafety(false);
    const exec = arf.loadExecutable(drv.arf_data);
    if (exec == null) {
        sys.panic("Failed to load driver. Could not continue with execution");
    }
    const exec_ptr = kalloc.storeKernel(arf.Executable);
    exec_ptr.* = exec.?;
    const raw_drv = kalloc.storeKernel(RawDriver);
    raw_drv.* = RawDriver{ .typ = drv.type, .drv = drv, .exec = exec_ptr };
    return raw_drv;
}

pub fn loadDriver(rawDrv: *RawDriver) ?*LoadedDriver {
    @setRuntimeSafety(false);
    const loadedDrv = kalloc.storeKernel(LoadedDriver);
    loadedDrv.* = LoadedDriver{
        .typ = rawDrv.typ,
        .drv = rawDrv.drv,
        .functions = mem.Array(DriverFunction).initKernel(),
        .base_addr = 0,
        .is_loaded = false,
        .finalDrv = null,
    };

    const dataLength = rawDrv.exec.data.len;
    out.print("Loading driver with length: ");
    out.printn(dataLength);
    out.println("");
    const dataPtr = kalloc.requestKernel(dataLength);
    if (dataPtr == null) {
        sys.panic("Failed to allocate memory for driver data");
    }

    loadedDrv.base_addr = @intFromPtr(dataPtr);

    const NativeSymbols = [_]NativeFunction{
        .{ .name = "avprint", .addr = @intFromPtr(&out.print) },
    };

    var patched = mem.Array([]const u8).initKernel();

    // Patch the symbols that the driver API exports
    for (rawDrv.exec.fixes) |fix| {
        for (NativeSymbols) |sym| {
            if (mem.compareBytes(u8, fix.name, sym.name)) {
                out.print("Patched native symbol ");
                out.print(sym.name);
                out.print(" at address: ");
                out.printHex(sym.addr);
                out.println("");
                fix.patch(sym.addr, rawDrv.exec);
                patched.append(fix.name);
            }
        }
    }

    for (rawDrv.exec.symbols) |symbol| {
        loadedDrv.functions.append(.{
            .name = symbol.name,
            .addr = symbol.offset + loadedDrv.base_addr,
        });
    }

    for (rawDrv.exec.fixes) |fix| {
        if (!mem.contains([]const u8, patched.coerce(), fix.name)) {
            var addr: ?usize = null;
            for (rawDrv.exec.symbols) |symbol| {
                if (mem.compareBytes(u8, symbol.name, fix.name)) {
                    addr = symbol.offset;
                }
            }
            if (addr == null) {
                out.print("Could not find symbol ");
                out.print(fix.name);
                out.println("");
                continue;
            }
            out.print("Patched driver symbol ");
            out.print(fix.name);
            out.print(" at address: ");
            out.printHex(addr.? + loadedDrv.base_addr);
            out.println("");
            fix.patch(addr.? + loadedDrv.base_addr, rawDrv.exec);
            patched.append(fix.name);
        }
    }

    for (0..rawDrv.exec.data.len) |i| {
        dataPtr.?[i] = rawDrv.exec.data[i];
    }

    return loadedDrv;
}

fn buildFunctionTable(rawDrv: *RawDriver, loadedDrv: *LoadedDriver) void {
    @setRuntimeSafety(false);
    for (0..rawDrv.exec.symbols.len) |i| {
        const symbol = &rawDrv.exec.symbols[i];

        if (mem.contains([]const u8, WANTED_FUNCTIONS, symbol.name)) {
            loadedDrv.functions.append(.{
                .name = symbol.name,
                .addr = symbol.offset + loadedDrv.base_addr,
            });
        }
    }
}

pub fn executeDriver(loadedDrv: *LoadedDriver) void {
    @setRuntimeSafety(false);
    switch (loadedDrv.typ) {
        .Utility => {
            var init: ?*fn () drv_type.AveryStatus = null;
            var destroy: ?*fn () drv_type.AveryStatus = null;
            for (loadedDrv.functions.coerce()) |fun| {
                if (mem.compareBytes(u8, fun.name, "init")) {
                    init = @ptrFromInt(fun.addr);
                } else if (mem.compareBytes(u8, fun.name, "destroy")) {
                    destroy = @ptrFromInt(fun.addr);
                }
            }
            if (init == null or destroy == null) {
                sys.panic("Could not initialize driver. The code is missing the init or destroy function");
            }
            loadedDrv.finalDrv = .{ .utility = .{
                .init = init.?,
                .destroy = destroy.?,
            } };
            out.switchToSerial();
            mem.inspectChunk(@intFromPtr(loadedDrv.finalDrv.?.utility.init), 16);
            var status = loadedDrv.finalDrv.?.utility.init();
            while (true) {}
            if (status == drv_type.STATUS_OK) {
                status = loadedDrv.finalDrv.?.utility.destroy();
                if (status != drv_type.STATUS_OK) {
                    sys.panic("Driver destruction failed");
                }
            } else {
                sys.panic("Driver initializiation failed");
            }
        },
        else => sys.panic("Driver not implemented yet"),
    }
}
