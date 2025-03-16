/*
 diskutil.c
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: Erase, reformat and disk utility actions command
 Copyright (c) 2025 Maxims Enterprise
*/

#include "common.h"
#include "console.h"
#include "disk/ata.h"
#include "disk/fat32.h"
#include "vga.h"

void disk_utility(str command) {
    if (strncmp(command, "erase", 5) == 0) {
        write("Are you sure you want to erase the disk? (y/n) ");
        str response = read_line("");
        if (response[0] == 'y') {
            write("Erasing disk...\n");
            fat32_erase_disk();
            write("Disk erased\n");
        } else {
            write("Operation canceled\n");
        }
    } else if (strncmp(command, "list", 4) == 0) {
        ata_scan_drives();
        DriveInfo *drives = get_connected_drives(&drive_count);
        for (int i = 0; i < drive_count; i++) {
            if (strncmp(drives[i].format, "None", 4) == 0) {
                continue;
            }
            write("Drive ");
            write_char(drives[i].label);
            write(" in ");
            write(drives[i].format);
            write("\n");
        }
    } else if (strncmp(command, "current", 7) == 0) {
        ata_scan_drives();
        DriveInfo *drives = get_connected_drives(&drive_count);
        for (int i = 0; i < drive_count; i++) {
            if (drives->bus == 0 && drives->drive == 0) {
                write("Current drive is ");
                write_char(drives->label);
                write(" in ");
                write(drives->format);
                write("\n");
                return;
            }
        }
    } else {
        write("Invalid use of 'disk' command\n");
        write("Usage: disk <command>\n");
    }
}
