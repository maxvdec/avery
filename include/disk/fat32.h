/*
 fat32.h
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: FAT32 implementation definitions
 Copyright (c) 2025 Maxims Enterprise
*/

#ifndef _FAT32_H
#define _FAT32_H

#include "common.h"

typedef struct {
    u8 boot_flag;
    u8 chs_begin[3];
    u8 partition_type;
    u8 chs_end[3];
    u32 lba_begin;
    u32 sectors;
} __attribute__((packed)) fat32_partition;

typedef struct {
    u8 boot_code[446];
    fat32_partition partitions[4];
    u16 signature;
} __attribute__((packed)) mbr_t;

extern u32 fat32_partition_lba;

typedef struct {
    u8 jmp_boot[3];
    u8 oem_name[8];
    u16 bytes_per_sector;
    u8 sectors_per_cluster;
    u16 reserved_sectors;
    u8 fat_count;
    u16 root_entries;
    u16 total_sectors_16;
    u8 media_descriptor;
    u16 sectors_per_fat_16;
    u16 sectors_per_track;
    u16 heads;
    u32 hidden_sectors;
    u32 total_sectors_32;
    u32 sectors_per_fat;
    u16 flags;
    u16 fat_version;
    u32 root_cluster;
    u16 fsinfo_sector;
    u16 backup_boot_sector;
    u8 reserved[12];
    u8 drive_number;
    u8 reserved2;
    u8 boot_signature;
    u32 volume_id;
    u8 volume_label[11];
    u8 fs_type[8];
} __attribute__((packed)) fat32_bpb_t;

typedef struct {
    u32 cluster;
    u32 size;
} fat32_file_t;

static fat32_bpb_t public_bpb = {0};

void fat32_read_mbr();
void fat32_read_boot_sector();
u32 fat32_get_next_cluster(u32 cluster);
void fat32_list_cluster(u32 cluster);
u32 fat32_find_cluster(const str path);
fat32_file_t fat32_find_entry(u32 cluster, const str name);
void fat32_list_path(const str path);
void fat32_lfn_to_filename(str dest, u8 *entry);
void fat32_format_filename(str filename, bool is_directory);
void fat32_reverse_filename(str filename, bool is_directory);
char *to_fat32_8dot3_format(str filename);
str fat32_read_file(const str path);
fat32_file_t fat32_find_file(const str path);
u32 fat32_create_directory(const str path);

#endif // _FAT32_H
