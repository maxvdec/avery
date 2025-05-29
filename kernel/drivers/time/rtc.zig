const str = @import("string");
const sys = @import("system");

const RTC_SECONDS = 0x00;
const RTC_MINUTES = 0x02;
const RTC_HOURS = 0x04;
const RTC_DAY_OF_MONTH = 0x07;
const RTC_MONTH = 0x08;
const RTC_YEAR = 0x09;
const RTC_CENTURY = 0x32;

const CMOS_ADDR = 0x70;
const CMOS_DATA = 0x71;

const UNIX_EPOCH_YEAR = 1970;

pub const DateTime = struct { year: u16, month: u8, day: u8, hour: u8, minute: u8, second: u8 };

fn readCMOS(reg: u8) u8 {
    @setRuntimeSafety(false);
    const port = @as(u16, CMOS_ADDR);
    const data_port = @as(u16, CMOS_DATA);
    sys.outb(port, reg);
    return sys.inb(data_port);
}

fn bcdToBinary(bcd: u8) u8 {
    return (bcd & 0x0F) + ((bcd >> 4) * 10);
}

fn isRTCInBCD() bool {
    const statusB = readCMOS(0x0B);
    return (statusB & 0x04) != 0; // Check the BCD mode bit
}

pub fn readRTC() DateTime {
    const is_bcd = isRTCInBCD();

    var second = readCMOS(RTC_SECONDS);
    var minute = readCMOS(RTC_MINUTES);
    var hour = readCMOS(RTC_HOURS);
    var day = readCMOS(RTC_DAY_OF_MONTH);
    var month = readCMOS(RTC_MONTH);
    var year = readCMOS(RTC_YEAR);
    var century = readCMOS(RTC_CENTURY);

    if (is_bcd) {
        second = bcdToBinary(second);
        minute = bcdToBinary(minute);
        hour = bcdToBinary(hour);
        day = bcdToBinary(day);
        month = bcdToBinary(month);
        year = bcdToBinary(year);
        century = bcdToBinary(century);
    }

    const full_year = @as(u16, century) * 100 + @as(u16, year);

    return DateTime{
        .year = full_year,
        .month = month,
        .day = day,
        .hour = hour,
        .minute = minute,
        .second = second,
    };
}

pub fn isLeapYear(year: u16) bool {
    if (year % 4 != 0) return false;
    if (year % 100 == 0 and year % 400 != 0) return false;
    return true;
}

const DAYS_IN_MONTH = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

pub fn dateTimeToUnix(dt: DateTime) u64 {
    var unix_time: u64 = 0;

    var year = UNIX_EPOCH_YEAR;
    while (year < dt.year) : (year += 1) {
        if (isLeapYear(year)) {
            unix_time += 366 * 24 * 60 * 60;
        } else {
            unix_time += 365 * 24 * 60 * 60;
        }
    }

    var month: u8 = 1;
    while (month < dt.month) : (month += 1) {
        var days_this_month = DAYS_IN_MONTH[month - 1];
        if (month == 2 and isLeapYear(dt.year)) {
            days_this_month = 29;
        }
        unix_time += @as(u64, days_this_month) * 24 * 60 * 60;
    }

    unix_time += @as(u64, dt.day - 1) * 24 * 60 * 60;

    unix_time += @as(u64, dt.hour) * 60 * 60;
    unix_time += @as(u64, dt.minute) * 60;
    unix_time += @as(u64, dt.second);

    return unix_time;
}

pub fn getUnixTime() u64 {
    const dt = readRTC();
    return dateTimeToUnix(dt);
}

pub fn unixToDateTime(unix_time: u64) DateTime {
    var remaining_seconds = unix_time;
    var year: u16 = UNIX_EPOCH_YEAR;

    while (true) {
        const seconds_in_year = if (isLeapYear(year)) 366 * 24 * 60 * 60 else 365 * 24 * 60 * 60;
        if (remaining_seconds < seconds_in_year) break;
        remaining_seconds -= seconds_in_year;
        year += 1;
    }

    var month: u8 = 1;
    while (month <= 12) {
        var days_this_month = DAYS_IN_MONTH[month - 1];
        if (month == 2 and isLeapYear(year)) {
            days_this_month = 29;
        }
        const seconds_this_month = @as(u64, days_this_month) * 24 * 60 * 60;
        if (remaining_seconds < seconds_this_month) break;
        remaining_seconds -= seconds_this_month;
        month += 1;
    }

    const day = @as(u8, @intCast(remaining_seconds / (24 * 60 * 60))) + 1;
    remaining_seconds %= (24 * 60 * 60);

    const hour = @as(u8, @intCast(remaining_seconds / (60 * 60)));
    remaining_seconds %= (60 * 60);
    const minute = @as(u8, @intCast(remaining_seconds / 60));
    const second = @as(u8, @intCast(remaining_seconds % 60));

    return DateTime{
        .year = year,
        .month = month,
        .day = day,
        .hour = hour,
        .minute = minute,
        .second = second,
    };
}

pub fn formatDateTime(dt: DateTime) []const u8 {
    var buffer = str.DynamicString.init("");
    buffer.pushInt(dt.day);
    buffer.pushChar('/');
    buffer.pushInt(dt.month);
    buffer.pushChar('/');
    buffer.pushInt(dt.year);
    buffer.pushChar(' ');
    buffer.pushInt(dt.hour);
    buffer.pushChar(':');
    buffer.pushInt(dt.minute);
    buffer.pushChar(':');
    buffer.pushInt(dt.second);
    return buffer.snapshot();
}
