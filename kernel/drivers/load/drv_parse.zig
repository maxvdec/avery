const arf = @import("arf");
const driver = @import("drv_load");
const kalloc = @import("kern_allocator");
const mem = @import("memory");
const out = @import("output");
const sys = @import("system");

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
};

pub const NativeFunction = struct {
    name: []const u8,
    addr: usize,
};

const WANTED_FUNCTIONS = &[_][]const u8{ "init", "destroy" };

pub fn makeRawDriver(drv: driver.Driver) *RawDriver {
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
    const loadedDrv = kalloc.storeKernel(LoadedDriver);
    loadedDrv.* = LoadedDriver{
        .typ = rawDrv.typ,
        .drv = rawDrv.drv,
        .functions = mem.Array(DriverFunction).initKernel(),
        .base_addr = 0,
        .is_loaded = false,
    };

    const NATIVE_FUNCTIONS = &[_]NativeFunction{
        .{ .name = "avprint", .addr = @intFromPtr(&out.println) },
        .{ .name = "native_function_2", .addr = 0x5678 },
    };

    // First, we should go and replace the driver's interface fixes
    for (0..rawDrv.exec.fixes.len) |i| {
        var fix = rawDrv.exec.fixes[i];
        for (NATIVE_FUNCTIONS) |nativeFunc| {
            if (mem.compareBytes(u8, fix.name, nativeFunc.name)) {
                fix.patch(nativeFunc.addr, rawDrv.exec);
            }
        }
    }

    const code_size = rawDrv.exec.data.len;
    const driver_memory = kalloc.requestKernel(code_size);
    if (driver_memory == null) {
        sys.panic("Cannot start system. Allocating memory for a driver crashed");
    }

    for (0..code_size) |i| {
        driver_memory.?[i] = rawDrv.exec.data[i];
    }

    loadedDrv.base_addr = @intFromPtr(driver_memory.?);

    for (0..rawDrv.exec.fixes.len) |i| {
        var fix = rawDrv.exec.fixes[i];
        for (0..rawDrv.exec.symbols.len) |j| {
            const symbol = &rawDrv.exec.symbols[j];
            if (mem.compareBytes(u8, fix.name, symbol.name)) {
                fix.patch(symbol.offset + loadedDrv.base_addr, rawDrv.exec);
            }
        }
    }

    buildFunctionTable(rawDrv, loadedDrv);

    loadedDrv.is_loaded = true;

    return loadedDrv;
}

fn buildFunctionTable(rawDrv: *RawDriver, loadedDrv: *LoadedDriver) void {
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
