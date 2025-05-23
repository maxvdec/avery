const mem = @import("memory");
const sys = @import("system");
const str = @import("string");

const SERIAL_PORT: u16 = 0x3F8;

pub fn initSerial() void {
    sys.outb(SERIAL_PORT + 1, 0x00);
    sys.outb(SERIAL_PORT + 3, 0x80);
    sys.outb(SERIAL_PORT + 0, 0x03);
    sys.outb(SERIAL_PORT + 1, 0x00);
    sys.outb(SERIAL_PORT + 3, 0x03);
    sys.outb(SERIAL_PORT + 2, 0xC7);
    sys.outb(SERIAL_PORT + 4, 0x0B);
    sys.outb(SERIAL_PORT + 5, 0x01);
}

fn isTransmitReady() bool {
    return (sys.inb(SERIAL_PORT + 5) & 0x20) != 0;
}

pub fn writeChar(c: str.char) void {
    while (!isTransmitReady()) {}
    sys.outb(SERIAL_PORT, c);
}

pub fn writeString(s: str.String) void {
    for (s.iterate()) |c| {
        if (c == '\n') writeChar('\r');
        writeChar(c);
    }
}
