pub const char = u8;

pub const String = struct {
    data: []const u8,

    pub fn init(comptime str: []const u8) String {
        return String{
            .data = str,
        };
    }

    pub fn fromRuntime(comptime str: []const u8) String {
        return String{
            .data = str,
        };
    }

    pub fn length(self: *String) usize {
        return self.data.len;
    }

    pub fn join(self: *const String, other: String) String {
        const new_length = self.length() + other.length();
        var result = []u8{0} ** new_length;

        var i: usize = 0;
        for (self.data) |c| {
            result[i] = c;
            i += 1;
        }

        for (other.data, 0..) |c, j| {
            result[self.length() + j] = c;
        }

        return String{
            .data = result,
        };
    }

    pub fn getPointer(self: *String) [*]const u8 {
        return self.data.ptr;
    }

    pub fn iterate(self: *String) []const u8 {
        return self.data;
    }

    pub fn at(self: String, index: usize) u8 {
        return self.data[index];
    }

    pub fn findChar(self: *String, match: char, matches: u16) []u32 {
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
