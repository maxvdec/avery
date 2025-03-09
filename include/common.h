/*
 common.h
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: Common standard types and stdlib for the kernel development
 Copyright (c) 2025 Maxims Enterprise
*/

#ifndef _COMMON_H
#define _COMMON_H

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long long u64;

typedef signed char i8;
typedef signed short i16;
typedef signed int i32;
typedef signed long long i64;

#define NULL ((void *)0)

#define BUILD "dev0.0.1/2025"

#define true 1
#define false 0

#define TAB_WIDTH 4

typedef unsigned int size;
typedef u8 bool;

typedef char *str;

u8 *memcopy(u8 *dest, const u8 *src, size count);
u8 *memset(u8 *dest, u8 val, size count);
u16 *memset_w(u16 *dest, u16 val, size count);
u8 *memmove(u8 *dest, const u8 *src, size count);
u32 memcmp(const u8 *s1, const u8 *s2, size count);

size strlen(const str s);

u8 inb(u16 port);
void outb(u16 port, u8 data);
u16 inw(u16 port);
void outw(u16 port, u16 data);

void io_wait();

void wait(u32 ticks);

str read_line(str prompt);
str read_line_buffered(str prompt, u32 buffer_size);

void write_hex(u32 num);

void *malloc(size size);
void free(void *ptr);

int strncmp(const str s1, const str s2, size count);
void tolower(str s);
void toupper(str s);
void trim(str s);
str concat(str s1, str s2);
str strchr(str s, int c);
str strncpy(str dest, const str src, size count);
bool ends_with(const str s, char c);
bool contains(const str s, char c);
int strfind(const str s, char c);
str strrchr(str s, char c);
bool strcontains(const str s, const str chain);

void list_dir(const str path);
bool dir_exists(const str path);
bool file_exists(const str path);
str read_file(const str path);
bool create_dir(const str path);
bool create_file(const str path);
bool write_to_file(const str path, const str contents);

void panic(const str message);
void boot_panic(const str message);

#endif // _COMMON_H
