/*
 ata.c
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: ATA Functionality implementation
 Copyright (c) 2025 Maxims Enterprise
*/

#include "disk/ata.h"
#include "common.h"
#include "vga.h"

bool ata_detect(u8 bus, u8 drive) {
    u16 io = (bus == 0) ? 0x1F0 : 0x170;
    u8 status;

    outb(io + 6, 0xA0 | (drive << 4));
    io_wait();

    status = inb(io + 7);
    if (status == 0xFF)
        return false;

    return true;
}

bool ata_identify(u8 bus, u8 drive, u16 *buffer) {
    u16 io = (bus == 0) ? 0x1F0 : 0x170;

    outb(io + 6, 0xA0 | (drive << 4));
    io_wait();

    outb(io + 7, 0xEC);
    io_wait();

    if (inb(io + 7) == 0) {
        return false;
    }

    for (u32 i = 0; i < 256; i++) {
        buffer[i] = inw(io);
    }

    return true;
}

void ata_read_sector(u8 bus, u8 drive, u32 lba, u8 *buffer) {
    u16 io = (bus == 0) ? 0x1F0 : 0x170;

    outb(io + 6, 0xE0 | (drive << 4) | ((lba >> 24) & 0x0F));

    outb(io + 1, 0x00);
    outb(io + 2, 1);
    outb(io + 3, (u8)(lba));
    outb(io + 4, (u8)(lba >> 8));
    outb(io + 5, (u8)(lba >> 16));

    outb(io + 7, 0x20);

    while (!(inb(io + 7) & 0x08))
        ;

    for (u32 i = 0; i < 256; i++) {
        u16 data = inw(io);
        buffer[i * 2] = data & 0xFF;
        buffer[i * 2 + 1] = (data >> 8) & 0xFF;
    }
}

void ata_write_sector(u8 bus, u8 drive, u32 lba, u8 *buffer) {
    u16 io = (bus == 0) ? 0x1F0 : 0x170;

    if (lba < 0x20 || lba >= 0x1000) {
        write("ERROR: Attempting to write to a reserved/system sector.\n");
        return;
    }

    outb(io + 6, 0xE0 | (drive << 4) | ((lba >> 24) & 0x0F));

    outb(io + 1, 0x00);
    outb(io + 2, 1);
    outb(io + 3, (u8)(lba));
    outb(io + 4, (u8)(lba >> 8));
    outb(io + 5, (u8)(lba >> 16));

    outb(io + 7, 0x30);

    u32 timeout = 10000;
    while (!(inb(io + 7) & 0x08)) {
        if (--timeout == 0) {
            panic("ERROR: ATA write timeout.\n");
            return;
        }
    }

    u8 status = inb(io + 7);
    if (status & 0x01) {
        panic("ERROR: ATA write failed (status error).\n");
        return;
    }

    for (u32 i = 0; i < 256; i++) {
        u16 data = (buffer[i * 2 + 1] << 8) | buffer[i * 2];
        outw(io, data);
    }

    timeout = 10000;
    while (inb(io + 7) & 0x80) {
        if (--timeout == 0) {
            status = inb(io + 7);
            if (status & 0x01) {
                write("ERROR: ATA write failed (status error).\n");
            } else if (status & 0x02) {
                write("ERROR: ATA write failed (drive is busy).\n");
            } else if (status & 0x20) {
                write("ERROR: ATA write failed (write fault).\n");
            } else if (status & 0x40) {
                write("ERROR: ATA write failed (seek error).\n");
            } else {
                write("ERROR: ATA write timeout after writing data.\n");
            }
            return;
        }
    }

    status = inb(io + 7);
    if (status & 0x01) {
        write("ERROR: ATA write failed (post-write error).\n");
    }
}

int drive_count = 0;
DriveInfo drives[MAX_DRIVES];

void ata_scan_drives() {
    drive_count = 0;
    char label = 'A';

    for (u8 bus = 0; bus < 2; bus++) {
        for (u8 drive = 0; drive < 2; drive++) {
            if (ata_detect(bus, drive)) {
                if (drive_count < MAX_DRIVES) {
                    drives[drive_count].label = label;
                    drives[drive_count].bus = bus;
                    drives[drive_count].drive = drive;
                    ata_check_format(bus, drive, drives[drive_count].format);
                    drive_count++;

                    if (label < 'Z') {
                        label++;
                    }
                }
            }
        }
    }
}

DriveInfo *get_connected_drives(int *count) {
    *count = drive_count;
    return drives;
}

void ata_check_format(u8 bus, u8 drive, char *format) {
    u16 buffer[256];
    if (ata_identify(bus, drive, buffer)) {
        u16 fs_type = buffer[54];
        if (fs_type & 0x4000) {
            strncpy(format, "FAT32", 5);
        } else if (fs_type & 0x2000) {
            strncpy(format, "FAT16", 5);
        } else if (fs_type & 0x1000) {
            strncpy(format, "FAT12", 5);
        } else {
            strncpy(format, "Unknown", 8);
        }
    } else {
        strncpy(format, "None", 4);
    }
}
