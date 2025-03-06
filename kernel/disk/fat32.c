/*
 fat32.c
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: FAT32 function implementation
 Copyright (c) 2025 Maxims Enterprise
*/

#include "disk/fat32.h"
#include "common.h"
#include "disk/ata.h"
#include "vga.h"

u32 fat32_partition_lba = 0;

void fat32_read_mbr() {
    u8 buffer[512];
    mbr_t *mbr = (mbr_t *)buffer;

    ata_read_sector(0, 0, 0, buffer);

    if (mbr->signature != 0xAA55) {
        write("Invalid MBR signature\n");
        return;
    }

    for (int i = 0; i < 4; i++) {
        if (mbr->partitions[i].partition_type == 0x0B ||
            mbr->partitions[i].partition_type == 0x0C) {
            fat32_partition_lba = mbr->partitions[i].lba_begin;

            return;
        }
    }

    write("ERROR: No FAT32 partition found!\n");
}

void fat32_lfn_to_filename(str dest, u8 *entry) {
    int i = 0;
    for (int j = 0; j < 5; j++) {
        if (entry[1 + j * 2] != 0xFF) {
            dest[i++] = entry[1 + j * 2];
        }
    }
    for (int j = 0; j < 6; j++) {
        if (entry[2 + j * 2] != 0xFF) {
            dest[i++] = entry[2 + j * 2];
        }
    }
    for (int j = 0; j < 2; j++) {
        if (entry[3 + j * 2] != 0xFF) {
            dest[i++] = entry[3 + j * 2];
        }
    }
    dest[i] = '\0';
}

void fat32_read_boot_sector() {
    u8 buffer[512];

    ata_read_sector(0, 0, fat32_partition_lba, buffer);

    fat32_bpb_t *bpb = (fat32_bpb_t *)buffer;

    if (bpb->fs_type[0] != 'F' || bpb->fs_type[1] != 'A' ||
        bpb->fs_type[2] != 'T' || bpb->fs_type[3] != '3' ||
        bpb->fs_type[4] != '2' || bpb->fs_type[5] != ' ' ||
        bpb->fs_type[6] != ' ' || bpb->fs_type[7] != ' ') {
        write("ERROR: Not a FAT32 filesystem!\n");
        return;
    }

    memcopy((u8 *)&public_bpb, buffer, sizeof(fat32_bpb_t));
    return;
}

u32 fat32_get_next_cluster(u32 cluster) {
    u8 buffer[512];

    u32 fat_lba =
        fat32_partition_lba + public_bpb.reserved_sectors + (cluster * 4) / 512;
    ata_read_sector(0, 0, fat_lba, buffer);

    u32 next_cluster = *((u32 *)&buffer[(cluster * 4) % 512]) & 0x0FFFFFFF;

    return next_cluster;
}

void fat32_list_cluster(u32 cluster) {
    u8 buffer[512];
    char filename[256];

    if (cluster == 0) {
        cluster = public_bpb.root_cluster;
    }

    while (1) {
        u32 lba = fat32_partition_lba + public_bpb.reserved_sectors +
                  (public_bpb.fat_count * public_bpb.sectors_per_fat) +
                  ((cluster - 2) * public_bpb.sectors_per_cluster);

        for (u32 i = 0; i < public_bpb.sectors_per_cluster; i++) {
            ata_read_sector(0, 0, lba + i, buffer);

            int lfn_index = -1;

            for (int j = 0; j < 512; j += 32) {
                u8 *entry = &buffer[j];

                if (entry[0] == 0x00) {
                    return;
                }

                if (entry[0] == 0xE5) {
                    continue;
                }

                if (entry[11] == 0x0F) {
                    if (lfn_index == -1) {
                        memset((u8 *)filename, 0, sizeof(filename));
                    }
                    fat32_lfn_to_filename(filename + lfn_index * 13, entry);
                    lfn_index++;

                    continue;
                }

                if (lfn_index >= 0) {
                    lfn_index = -1;

                    if (entry[11] & 0x10) {
                        fat32_format_filename(filename, true);
                        write(filename);
                        write("/\n");
                    } else {
                        fat32_format_filename(filename, false);
                        write(filename);
                        write("\n");
                    }
                } else {
                    char short_filename[12];
                    for (int k = 0; k < 11; k++) {
                        short_filename[k] = entry[k];
                    }
                    short_filename[11] = '\0';

                    tolower(short_filename);

                    if (entry[11] & 0x10) {
                        trim(short_filename);
                        write(short_filename);
                        write("/\n");
                    } else {
                        fat32_format_filename(short_filename, false);
                        write(short_filename);
                        write("\n");
                    }
                }
            }
        }
        cluster = fat32_get_next_cluster(cluster);

        if (cluster >= 0x0FFFFFF8) {
            break;
        }
    }
}

void fat32_reverse_filename(str filename, bool is_directory) {
    char name[9] = {0};
    char extension[4] = {0};

    char *dot_pos = strchr(filename, '.');
    if (dot_pos) {
        size name_len = dot_pos - filename;
        size ext_len = strlen(filename) - name_len - 1;

        if (name_len > 8) {
            name_len = 8;
        }

        if (ext_len > 3) {
            ext_len = 3;
        }

        strncpy(name, filename, name_len);
        strncpy(extension, dot_pos + 1, ext_len);
    } else {
        size name_len = strlen(filename);
        if (name_len > 8) {
            name_len = 8;
        }

        strncpy(name, filename, name_len);
    }

    for (int i = strlen(name); i < 8; i++) {
        name[i] = ' ';
    }

    for (int i = strlen(extension); i < 3; i++) {
        extension[i] = ' ';
    }

    for (int i = 0; i < 8; i++) {
        filename[i] = name[i];
    }

    for (int i = 0; i < 3; i++) {
        filename[i + 8] = extension[i];
    }

    if (is_directory) {
        filename[11] |= 0x10;
    }

    filename[11] = '\0';
}

u32 fat32_find_cluster(const str path) {
    if (path[0] != '/') {
        write("ERROR: Invalid path (must start with /)\n");
        return 0xFFFFFFFF;
    }

    u32 cluster = public_bpb.root_cluster;

    if (path[1] == '\0') {
        return cluster;
    }

    char name[12];
    const char *token = path + 1;

    while (*token) {
        int len = 0;
        while (*token != '/' && *token != '\0' && len < 11) {
            name[len++] = *token++;
        }
        name[len] = '\0';

        if (*token == '/')
            token++;

        cluster = fat32_find_entry(cluster, name).cluster;
        if (cluster == 0xFFFFFFFF) {
            return 0xFFFFFFFF;
        }
    }

    return cluster;
}

fat32_file_t fat32_find_file(const str path) {
    if (path[0] != '/') {
        write("ERROR: Invalid path (must start with /)\n");
        return (fat32_file_t){0xFFFFFFFF, 0};
    }

    u32 cluster = public_bpb.root_cluster;

    if (path[1] == '\0') {
        return (fat32_file_t){cluster, 0};
    }

    char name[12];
    const char *token = path + 1;
    fat32_file_t file = {cluster, 0};

    while (*token) {
        int len = 0;
        while (*token != '/' && *token != '\0' && len < 11) {
            name[len++] = *token++;
        }
        name[len] = '\0';

        if (*token == '/')
            token++;

        file = fat32_find_entry(cluster, name);
        if (file.cluster == 0xFFFFFFFF) {
            return (fat32_file_t){0xFFFFFFFF, 0};
        }

        cluster = file.cluster;
    }

    return file;
}

void fat32_list_path(const str path) {
    u32 cluster = fat32_find_cluster(path);
    if (cluster == 0xFFFFFFFF) {
        write("ERROR: Path not found\n");
        return;
    }

    fat32_list_cluster(cluster);
}

fat32_file_t fat32_find_entry(u32 cluster, const str name) {

    u8 buffer[512];

    while (1) {
        u32 lba = fat32_partition_lba +
                  (public_bpb.reserved_sectors +
                   (public_bpb.fat_count * public_bpb.sectors_per_fat) +
                   ((cluster - 2) * public_bpb.sectors_per_cluster));

        for (u32 i = 0; i < public_bpb.sectors_per_cluster; i++) {
            ata_read_sector(0, 0, lba + i, buffer);

            for (int j = 0; j < 512; j += 32) {
                u8 *entry = &buffer[j];

                if (entry[0] == 0x00) {
                    return (fat32_file_t){0xFFFFFFFF, 0};
                }
                if (entry[0] == 0xE5) {
                    continue;
                }
                if (entry[11] == 0x0F) {
                    continue;
                }

                char entry_name[12];
                int k = 0;

                for (k = 0; k < 8 && entry[k] != ' '; k++) {
                    entry_name[k] = entry[k];
                }

                if (entry[8] != ' ') {
                    entry_name[k++] = '.';
                    for (int m = 0; m < 3 && entry[8 + m] != ' '; m++) {
                        entry_name[k++] = entry[8 + m];
                    }
                }

                entry_name[k] = '\0';

                if (strncmp(entry_name, name, 11) == 0) {
                    u32 low = *((u16 *)&entry[26]);
                    u32 high = *((u16 *)&entry[20]);
                    u32 cluster_number = ((high << 16) | low) & 0x0FFFFFFF;

                    return (fat32_file_t){cluster_number, *((u32 *)&entry[28])};
                }
            }
        }

        cluster = fat32_get_next_cluster(cluster);
        if (cluster >= 0x0FFFFFF8) {
            break;
        }
    }

    return (fat32_file_t){0xFFFFFFFF, 0}; // Not found
}

void fat32_format_filename(str filename, bool is_directory) {
    if (is_directory) {
        return;
    }
    char name[9];
    char extension[4];

    for (int i = 0; i < 8; i++) {
        name[i] = filename[i];
    }
    name[8] = '\0';

    for (int i = 8; i < 11; i++) {
        extension[i - 8] = filename[i];
    }
    extension[3] = '\0';

    trim(name);
    trim(extension);

    int i = 0;
    while (name[i] != '\0') {
        filename[i] = name[i];
        i++;
    }

    if (extension[0] != '\0') {
        filename[i++] = '.';
        int j = 0;
        while (extension[j] != '\0') {
            filename[i++] = extension[j++];
        }
    }

    filename[i] = '\0';
}

char *to_fat32_8dot3_format(str filename) {
    int i = 0, j = 0;
    char temp_name[20];
    char *formatted = (char *)malloc(60);

    if (filename[0] == '/') {
        filename++;
    }

    for (i = 0; filename[i] != '\0' && i < 12; i++) {
        temp_name[i] = filename[i];
    }
    temp_name[i] = '\0';

    toupper(temp_name);

    i = 0;
    while (temp_name[i] != '\0' && temp_name[i] != '.' && i < 8) {
        formatted[i] = temp_name[i];
        i++;
    }

    while (i < 8) {
        formatted[i++] = ' ';
    }

    if (temp_name[i] == '.') {
        i++;

        j = 0;
        while (temp_name[i] != '\0' && j < 3) {
            formatted[8 + j] = temp_name[i];
            i++;
            j++;
        }
    } else {
        int dot_pos = strfind(temp_name, '.');
        if (dot_pos != -1) {
            i = dot_pos + 1;
            j = 0;
            while (temp_name[i] != '\0' && j < 3) {
                formatted[8 + j] = temp_name[i];
                i++;
                j++;
            }
        }
    }

    while (j < 3) {
        formatted[8 + j++] = ' ';
    }

    formatted[11] = '\0';

    if (formatted[0] != '/') {
        formatted = concat("/", formatted);
    }
    return formatted;
}

str fat32_read_file(const str path) {
    fat32_file_t file = fat32_find_file(path);
    if (file.cluster == 0xFFFFFFFF) {
        return NULL;
    }

    u32 cluster = file.cluster;
    u32 size = file.size;

    u8 *buffer = (u8 *)malloc(size);
    if (buffer == NULL) {
        return NULL;
    }

    u32 lba = fat32_partition_lba +
              (public_bpb.reserved_sectors +
               (public_bpb.fat_count * public_bpb.sectors_per_fat) +
               ((cluster - 2) * public_bpb.sectors_per_cluster));

    u32 read_size = 0;

    while (read_size < size) {
        u8 sector_buffer[512];
        ata_read_sector(0, 0, lba, sector_buffer);

        u32 bytes_to_read = size - read_size;
        if (bytes_to_read > 512) {
            bytes_to_read = 512;
        }

        memcopy(buffer + read_size, sector_buffer, bytes_to_read);

        read_size += bytes_to_read;
        lba++;
    }

    return (str)buffer;
}

u32 fat32_create_directory(const str path) {
    if (path[0] != '/') {
        write("ERROR: Path must start with '/'\n");
        return 0xFFFFFFFF;
    }

    char parent_path[256];
    char dir_name[12];
    const char *last_slash = &path[strfind(path, '/')];

    if (!last_slash || last_slash == path) {
        write("ERROR: Invalid directory path\n");
        return 0xFFFFFFFF;
    }

    strncpy(parent_path, path, last_slash - path);
    parent_path[last_slash - path] = '\0';
    strncpy(dir_name, last_slash + 1, 11);
    dir_name[11] = '\0';

    u32 parent_cluster = fat32_find_cluster(parent_path);
    if (parent_cluster == 0xFFFFFFFF) {
        write("ERROR: Parent directory not found\n");
        return 0xFFFFFFFF;
    }

    fat32_file_t existing_dir = fat32_find_entry(parent_cluster, dir_name);
    if (existing_dir.cluster != 0xFFFFFFFF) {
        write("ERROR: Directory already exists\n");
        return 0xFFFFFFFF;
    }

    u32 new_cluster = fat32_find_cluster("/");
    if (new_cluster == 0xFFFFFFFF) {
        write("ERROR: Root directory not found\n");
        return 0xFFFFFFFF;
    }

    u8 buffer[512];
    u32 lba = fat32_partition_lba +
              (public_bpb.reserved_sectors +
               (public_bpb.fat_count * public_bpb.sectors_per_fat) +
               ((new_cluster - 2) * public_bpb.sectors_per_cluster));

    for (u32 i = 0; i < public_bpb.sectors_per_cluster; i++) {
        ata_read_sector(0, 0, lba + i, buffer);

        for (int j = 0; j < 512; j += 32) {
            u8 *entry = &buffer[j];

            if (entry[0] == 0x00 || entry[0] == 0xE5) {
                for (int k = 0; k < 11; k++) {
                    entry[k] = ' ';
                }

                strncpy((str)entry, dir_name, strlen(dir_name));
                entry[11] = 0x10;

                ata_write_sector(0, 0, lba + i, buffer);

                return new_cluster;
            }
        }
    }

    write("ERROR: Directory could not be created\n");
    return 0xFFFFFFFF;
}
