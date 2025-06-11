const mem = @import("memory");
const proc = @import("process");

pub const Architecture = enum(u8) {
    i386 = 1,
    x86_64 = 2,
    armv7 = 3,
    aarch64 = 4,
};

pub const Header = struct {
    version: []u8,
    architecture: Architecture,
    hostArchitecture: Architecture,
};

pub const SEC_READ = 0x0;
pub const SEC_WRITE = 0x2;
pub const SEC_EXECUTE = 0x4;
pub const SEC_INFO = 0x10;

pub const Section = struct {
    name: []const u8,
    offset: usize,
    permission: u8,
};

pub const SYM_RESOLVED = 0x0;
pub const SYM_UNRESOLVED = 0x1;
pub const SYM_MERGED = 0x2;

pub const SYM_LOCAL = 0x0;
pub const SYM_GLOBAL = 0x1;
pub const SYM_MIXED = 0x2;

pub const Symbol = struct {
    name: []const u8,
    resolution: u8,
    typ: u8,
    offset: usize,
};

const LIB_RESOLVED = 0x0;
const LIB_KERNEL = 0xFF;

pub const Library = struct {
    name: []const u8,
    visibility: u8,
};

pub const Fix = struct {
    name: []const u8,
    offset: usize,
};

pub const Executable = struct {
    header: Header,
    sections: []Section,
    symbols: []Symbol,
    libraries: []Library,
    fixes: []Fix,
    entryPoint: usize,
};
