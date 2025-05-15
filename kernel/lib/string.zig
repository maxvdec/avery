const mem = @import("memory");
pub const char = u8;

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

    pub fn isEqualTo(self: *const String, other: *const String) bool {
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
};

pub fn make(comptime str: []const u8) String {
    return String.init(str);
}

pub fn makeRuntime(str: []const u8) String {
    return String.fromRuntime(str);
}
