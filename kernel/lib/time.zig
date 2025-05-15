const pit = @import("pit");

pub const Instant = struct {
    seconds: u32 = 0,
    minutes: u32 = 0,
    milliseconds: u32 = 0,

    pub fn init() Instant {
        if (!pit.initialized) {
            pit.init();
        }
        return Instant{
            .seconds = pit.seconds,
            .minutes = @intCast(pit.seconds / 60),
            .milliseconds = pit.milliseconds,
        };
    }

    pub fn getSeconds(self: *Instant) u32 {
        return self.seconds;
    }

    pub fn getMinutes(self: *Instant) u32 {
        return self.minutes;
    }

    pub fn getMilliseconds(self: *Instant) u32 {
        return self.milliseconds;
    }

    pub fn getTime(self: *Instant) [3]u32 {
        return [3]u32{
            self.seconds,
            self.minutes,
            self.milliseconds,
        };
    }

    pub fn makeDelta(self: *Instant, other: *Instant) Instant {
        var seconds = self.seconds - other.seconds;
        var minutes = self.minutes - other.minutes;
        var milliseconds = self.milliseconds - other.milliseconds;

        if (milliseconds < 0) {
            milliseconds += 1000;
            seconds -= 1;
        }
        if (seconds < 0) {
            seconds += 60;
            minutes -= 1;
        }

        return Instant{
            .seconds = seconds,
            .minutes = minutes,
            .milliseconds = milliseconds,
        };
    }

    pub fn intoFuture(self: *Instant, future_milliseconds: u32) Instant {
        var new_milliseconds = self.milliseconds + future_milliseconds;
        var new_seconds = self.seconds;
        var new_minutes = self.minutes;

        if (new_milliseconds >= 1000) {
            new_seconds += @intCast(new_milliseconds / 1000);
            new_milliseconds = @intCast(new_milliseconds % 1000);
        }
        if (new_seconds >= 60) {
            new_minutes += @intCast(new_seconds / 60);
            new_seconds = @intCast(new_seconds % 60);
        }

        return Instant{
            .seconds = new_seconds,
            .minutes = new_minutes,
            .milliseconds = new_milliseconds,
        };
    }

    pub fn hasReached(self: *Instant, target: *Instant) bool {
        if (self.minutes > target.minutes) return true;
        if (self.minutes < target.minutes) return false;

        if (self.seconds > target.seconds) return true;
        if (self.seconds < target.seconds) return false;

        return self.milliseconds >= target.milliseconds;
    }
};

pub fn wait(milliseconds: u32) void {
    var start: Instant = Instant.init();

    var end: Instant = start.intoFuture(milliseconds);
    while (true) {
        var now: Instant = Instant.init();
        if (now.hasReached(&end)) {
            break;
        }
    }
}
