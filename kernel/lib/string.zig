const mem = @import("memory");
const alloc = @import("allocator");
const sys = @import("system");
pub const char = u8;

extern fn memcpy(
    dest: [*]u8,
    src: [*]const u8,
    len: usize,
) [*]u8;

pub const String = struct {
    data: []const u8,

    pub fn init(comptime str: []const u8) String {
        return String{
            .data = str,
        };
    }

    pub fn fromRuntime(str: []const u8) String {
        return String{
            .data = str,
        };
    }

    pub fn length(self: String) usize {
        return self.data.len;
    }

    pub fn join(self: String, other: String) ?String {
        const newLen = self.length() + other.length();
        if (newLen > 1024) {
            return null;
        }

        var buff: [1024]u8 = undefined;

        var i: usize = 0;
        while (i < self.length()) : (i += 1) {
            buff[i] = self.data[i];
        }

        var j: usize = 0;
        while (j < other.length()) : (j += 1) {
            buff[i + j] = other.data[j];
        }

        return String.fromRuntime(&buff);
    }

    pub fn coerce(self: String) []const u8 {
        return self.data;
    }

    pub fn getRawPointer(self: String) [*]const u8 {
        return self.data.ptr;
    }

    pub fn getPointer(self: String) mem.Pointer(u8) {
        return mem.Pointer(u8).init(self.data.ptr);
    }

    pub fn iterate(self: String) []const u8 {
        return self.data;
    }

    pub fn at(self: String, index: usize) u8 {
        return self.data[index];
    }

    pub fn trim(self: String) String {
        var start: usize = 0;
        var end: usize = self.length();

        while (start < end and (self.at(start) == ' ' or self.at(start) == '\n' or self.at(start) == '\r')) {
            start += 1;
        }

        while (end > start and (self.at(end - 1) == ' ' or self.at(end - 1) == '\n' or self.at(end - 1) == '\r')) {
            end -= 1;
        }

        return String.fromRuntime(self.data[start..end]);
    }

    pub fn findChar(self: String, match: char, matches: u16) []u32 {
        var currentMatch = 0;
        var i: usize = 0;
        var indices: [matches]u32 = undefined;
        while (i < self.length()) : (i += 1) {
            if (self.at(i) == match and currentMatch + 1 != matches + 1) {
                indices[currentMatch] = i;
                currentMatch += 1;
            }
        }

        return indices;
    }

    pub fn find(self: *const String, substring: []const u8) ?usize {
        if (substring.len == 0 or self.data.len == 0) return null;

        for (0..self.data.len - substring.len + 1) |i| {
            const str = makeRuntime(self.data[i .. i + substring.len]);
            const substr = makeRuntime(substring);
            if (str.isEqualTo(substr)) {
                return i;
            }
        }

        return null;
    }

    pub fn isEqualToStr(self: *const String, other: String) bool {
        if (self.data.len != other.data.len) {
            return false;
        }

        for (self.data, other.data) |a, b| {
            if (a != b) {
                return false;
            }
        }

        return true;
    }

    pub fn splitChar(self: String, delimiter: char) mem.Array(String) {
        @setRuntimeSafety(false);
        var result = mem.Array(String).init();

        if (self.length() == 0) {
            return result;
        }

        var start: usize = 0;
        var i: usize = 0;

        while (i < self.length()) {
            if (self.at(i) == delimiter) {
                if (start < i) {
                    const part = String.fromRuntime(self.data[start..i]);
                    result.append(part);
                } else {
                    result.append(String.init(""));
                }
                start = i + 1;
            }
            i += 1;
        }

        if (start < self.length()) {
            const remaining = String.fromRuntime(self.data[start..self.length()]);
            result.append(remaining);
        } else if (start == self.length()) {
            result.append(String.init(""));
        }

        return result;
    }

    pub fn isEqualTo(self: String, other: String) bool {
        if (self.data.len != other.data.len) {
            return false;
        }

        for (self.data, other.data) |a, b| {
            if (a != b) {
                return false;
            }
        }
        return true;
    }

    pub fn startsWith(self: String, prefix: String) bool {
        if (self.data.len < prefix.data.len) {
            return false;
        }

        for (0..prefix.data.len) |i| {
            if (self.data[i] != prefix.data[i]) {
                return false;
            }
        }
        return true;
    }

    pub fn copyToBuffer(self: String, buffer: [*]u8) void {
        const len = self.data.len;

        _ = memcpy(buffer, self.data.ptr, len);
    }
};

pub const DynamicString = struct {
    data: mem.Array(u8),

    pub fn init(comptime str: []const u8) DynamicString {
        return DynamicString{
            .data = mem.Array(u8).fromData(str),
        };
    }

    pub fn fromRuntime(str: []const u8) DynamicString {
        return DynamicString{
            .data = mem.Array(u8).fromRuntime(str),
        };
    }

    pub fn length(self: DynamicString) usize {
        return self.data.len;
    }

    pub fn getRawPointer(self: DynamicString) [*]const u8 {
        return self.data.ptr;
    }

    pub fn pushInt(self: *DynamicString, value: u32) void {
        if (value == 0) {
            self.pushChar('0');
            return;
        }

        var temp: [10]u8 = undefined;
        var i: usize = 0;
        var val = value;

        while (val > 0) {
            temp[i] = @intCast((val % 10) + '0');
            val /= 10;
            i += 1;
        }

        while (i > 0) {
            i -= 1;
            self.pushChar(temp[i]);
        }
    }

    pub fn pushStr(self: *DynamicString, str: []const u8) void {
        for (str) |c| {
            self.data.append(c);
        }
    }

    pub fn pushChar(self: *DynamicString, c: char) void {
        self.data.append(c);
    }

    pub fn snapshot(self: DynamicString) []const u8 {
        return self.data.iterate();
    }

    pub fn coerce(self: DynamicString) String {
        return String.fromRuntime(self.data.iterate());
    }
};

pub fn make(comptime str: []const u8) String {
    return String.init(str);
}

pub fn makeRuntime(str: []const u8) String {
    return String.fromRuntime(str);
}

pub fn makeOwned(str: []u8) String {
    @setRuntimeSafety(false);
    const raw = alloc.request(str.len);
    if (raw == null) {
        return String.init("");
    }

    const buffer: []u8 = raw.?[0..str.len];
    _ = sys.memcpy(buffer.ptr, str.ptr, str.len);
    return String.fromRuntime(buffer);
}
