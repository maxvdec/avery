/*
 serial.c
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: Serial COM1 bindings for writing to serial
 Copyright (c) 2025 Maxims Enterprise
*/

#include "drivers/serial.h"
#include "common.h"

void serial_init() {
    outb(SERIAL_PORT_COM1 + 1, 0x00);
    outb(SERIAL_PORT_COM1 + 3, 0x80);
    outb(SERIAL_PORT_COM1 + 0, 0x03);
    outb(SERIAL_PORT_COM1 + 1, 0x00);
    outb(SERIAL_PORT_COM1 + 3, 0x03);
    outb(SERIAL_PORT_COM1 + 2, 0xC7);
    outb(SERIAL_PORT_COM1 + 4, 0x0B);
}

u32 is_serial_read() { return inb(SERIAL_PORT_COM1 + 5) & 0x20; }

void serial_write(char data) {
    while (is_serial_read() == 0)
        ;
    outb(SERIAL_PORT_COM1, data);
}

void serial_write_str(char *data) {
    while (*data != 0) {
        serial_write(*data);
        data++;
    }
}
