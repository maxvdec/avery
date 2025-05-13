const str = @import("lib/string.zig");
const out = @import("lib/outputs.zig");

pub export fn kernel_main() noreturn {
    out.initOutputs();
    out.clear();
    while (true) {}
}
