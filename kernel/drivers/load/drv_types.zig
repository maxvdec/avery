const drv_parse = @import("drv_parse");
const drv_load = @import("drv_load");

// Types for interfacing with the code
pub const AveryStatus = i32;
pub const STATUS_OK = 0;
pub const STATUS_FAIL = -1;
pub const STATUS_TIMEOUT = -2;

pub const UtilityDriver = struct {
    init: *fn () AveryStatus = undefined,
    destroy: *fn () AveryStatus = undefined,
};

pub const Driver = union(enum) { utility: UtilityDriver };
