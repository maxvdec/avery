const arf = @import("arf");
const driver = @import("drv_load");
const kalloc = @import("kern_allocator");
const mem = @import("memory");
const out = @import("output");

pub const RawDriver = struct { typ: driver.DriverType, drv: driver.Driver, exec: *arf.Executable };

pub const DriverFunction = struct {
    name: []const u8,
    addr: usize,
};

pub const LoadedDriver = struct {
    typ: driver.DriverType,
    drv: driver.Driver,
    functions: mem.Array(DriverFunction),
};

pub const NativeFunction = struct {
    name: []const u8,
    addr: usize,
};

pub fn makeRawDriver(drv: driver.Driver) *RawDriver {
    const exec = arf.loadExecutable(drv.arf_data).?;
    const exec_ptr = kalloc.storeKernel(arf.Executable);
    exec_ptr.* = exec;
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
    };

    const nativeFunctions = &[_]NativeFunction{
        .{ .name = "avprint", .addr = @intFromPtr(&out.println) },
        .{ .name = "native_function_2", .addr = 0x5678 },
    };

    // First, we should go and replace the driver's interface fixes
    for (0..rawDrv.exec.fixes.len) |i| {
        var fix = rawDrv.exec.fixes[i];
        for (nativeFunctions) |nativeFunc| {
            if (mem.compareBytes(u8, fix.name, nativeFunc.name)) {
                fix.patch(nativeFunc.addr, rawDrv.exec);
            }
        }
    }

    return loadedDrv;
}
