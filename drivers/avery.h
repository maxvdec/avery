/*
 avery.h
 As part of the Avery project
 Created by Max Van den Eynde in 2025
 --------------------------------------------------
 Description: This header file contains declarations and definitions for the
 Avery interface. Copyright (c) 2025 Max Van den Eynde
*/

#ifndef AVERY_H

#define u8 char
#define u16 unsigned short
#define u32 unsigned int
#define u64 unsigned long long
#define bool char

#define avery_status int
#define avery_buf void *
#define AVERY_OK 0
#define AVERY_ERROR -1
#define AVERY_TIMEOUT -2

inline avery_status avery_status_from(int a) { return a; };

extern void avprint(const char *str);

/// Read a byte (u8) from the specified port.
extern u8 inb(u16 port);

/// Read a word (u16) from the specified port.
extern u16 inw(u16 port);

/// Read a long (u32) from the specified port.
extern u32 inl(u16 port);

/// Send a byte (u8) to the specified port.
extern void outb(u16 port, u8 value);

/// Send a word (u16) to the specified port.
extern void outw(u16 port, u16 value);

/// Send a long (u32) to the specified port.
extern void outl(u16 port, u32 value);

/// Enum representing different types of ports.
typedef enum {
    Pci,
    ComputerPin,
    Hdmi,
    Usb1,
    Usb2,
    Usb3,
} avery_port;

/// Struct that represents a device.
typedef struct {
    u16 manufacturer_id;
    u16 product_id;
    u8 subsystem_id;

    u32 driver_id;
    u8 driver_version;

    u32 device_port;
    avery_port connection_port;
} avery_device;

/// Struct that represents a filesystem.
typedef struct {
    const char name[32];
    const char acronym[8];
    const char version[8];
    const char designer[32];

    const char root_directory[32];
    int partition_count;
    int partition_size;
    int partition_offset;
    int region_size;
    int region_count;
} avery_fs;

/// Struct that represents a storage device.
typedef struct {
    avery_device device;
    int partition_count;
    int partition_size;
    int partition_offset;
    int region_size;
    int region_count;

    bool bootable;
} avery_stg;

#define AVERY_H
#endif // AVERY_H
