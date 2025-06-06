const str = @import("string");
const mem = @import("memory");
const alloc = @import("allocator");
const out = @import("output");

pub fn getParentPath(path: []const u8) []const u8 {
    if (mem.compareBytes(u8, path, "/")) {
        return path;
    }
    const last = mem.findLast(u8, path, '/');
    if (last == null) {
        return path;
    }

    const lastIndex = last.?;
    if (lastIndex == 0) {
        return "/";
    }
    return path[0..lastIndex];
}

pub fn joinPaths(base: []const u8, relative: []const u8) []const u8 {
    if (mem.compareBytes(u8, relative, "/")) {
        return base;
    }
    if (base.len == 0) {
        return relative;
    }

    const requiredSize: usize = base.len + relative.len + 2;

    const joined = alloc.request(requiredSize) orelse {
        out.println("Memory allocation failed in joinPaths");
        return "";
    };

    var i: usize = 0;

    while (i < base.len and i < requiredSize - 1) : (i += 1) {
        joined[i] = base[i];
    }

    if (i > 0 and joined[i - 1] != '/') {
        joined[i] = '/';
        i += 1;
    }

    var j: usize = 0;
    while (j < relative.len and i < requiredSize - 1) : (j += 1) {
        joined[i] = relative[j];
        i += 1;
    }

    joined[i] = 0;

    return joined[0..i];
}

pub fn joinPathsAsString(base: []const u8, relative: []const u8) str.String {
    if (mem.compareBytes(u8, relative, "/")) {
        return str.makeRuntime(base);
    }
    if (base.len == 0) {
        return str.makeRuntime(relative);
    }

    const requiredSize: usize = base.len + relative.len + 2;
    const joined = alloc.request(requiredSize) orelse {
        out.println("Memory allocation failed in joinPathsAsString");
        return str.make("");
    };

    var i: usize = 0;

    while (i < base.len and i < requiredSize - 1) : (i += 1) {
        joined[i] = base[i];
    }

    if (i > 0 and joined[i - 1] != '/') {
        joined[i] = '/';
        i += 1;
    }

    var j: usize = 0;
    while (j < relative.len and i < requiredSize - 1) : (j += 1) {
        joined[i] = relative[j];
        i += 1;
    }

    return str.makeRuntime(joined[0..i]);
}

pub fn getPathComponents(path: []const u8) [][256]u8 {
    const Component = [256]u8;
    var components = mem.Array(Component).init();
    var start: usize = 0;

    for (0..path.len) |i| {
        const c = path[i];
        if (c == '/') {
            if (i > start) {
                const slice = path[start..i];
                var comp: Component = undefined;
                @memset(&comp, 0);
                @memcpy(comp[0..slice.len], slice);
                components.append(comp);
            }
            start = i + 1;
        }
    }

    if (start < path.len) {
        const slice = path[start..];
        var comp: Component = undefined;
        @memset(&comp, 0);
        @memcpy(comp[0..slice.len], slice);
        components.append(comp);
    }

    return components.coerce();
}
