/*
 ata.h
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: Advanced Technology Attachment function definition
 Copyright (c) 2025 Maxims Enterprise
*/

#ifndef _ATA_H
#define _ATA_H

#include "common.h"

typedef struct {
    char label;
    u8 bus;
    u8 drive;
    char format[16];
} DriveInfo;

#define MAX_DRIVES 26 // From 'a' to 'z'

extern DriveInfo drives[MAX_DRIVES];
extern int drive_count;

bool ata_detect(u8 bus, u8 drive);
bool ata_identify(u8 bus, u8 drive, u16 *buffer);
void ata_read_sector(u8 bus, u8 drive, u32 lba, u8 *buffer);
void ata_write_sector(u8 bus, u8 drive, u32 lba, u8 *buffer);
void ata_scan_drives();
void ata_check_format(u8 bus, u8 drive, char *format);
DriveInfo *get_connected_drives(int *count);

#endif // _ATA_H
