/*
 common.c
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: Common stdlib function implementation
 Copyright (c) 2025 Maxims Enterprise
*/

#include "common.h"
#include "disk/fat32.h"
#include "drivers/keyboard.h"
#include "drivers/timer.h"
#include "vga.h"

u8 *memcopy(u8 *dest, const u8 *src, size count) {
    for (size i = 0; i < count; i++)
        dest[i] = src[i];
    return dest;
}

u8 *memset(u8 *dest, u8 val, size count) {
    for (size i = 0; i < count; i++)
        dest[i] = val;
    return dest;
}

u16 *memset_w(u16 *dest, u16 val, size count) {
    for (size i = 0; i < count; i++)
        dest[i] = val;
    return dest;
}

u8 *memmove(u8 *dest, const u8 *src, size count) {
    if (dest < src) {
        for (size i = 0; i < count; i++)
            dest[i] = src[i];
    } else {
        for (size i = count; i > 0; i--)
            dest[i - 1] = src[i - 1];
    }
    return dest;
}

u32 memcmp(const u8 *s1, const u8 *s2, size count) {
    for (size i = 0; i < count; i++) {
        if (s1[i] != s2[i])
            return s1[i] - s2[i];
    }
    return 0;
}

size strlen(const str s) {
    size i = 0;
    while (s[i] != '\0')
        i++;
    return i;
}

u8 inb(u16 port) {
    u8 data;
    __asm__ __volatile__("inb %1, %0" : "=a"(data) : "d"(port));
    return data;
}

void outb(u16 port, u8 data) {
    __asm__ __volatile__("outb %0, %1" : : "a"(data), "d"(port));
}

u16 inw(u16 port) {
    u16 data;
    __asm__ __volatile__("inw %1, %0" : "=a"(data) : "d"(port));
    return data;
}

void outw(u16 port, u16 data) {
    __asm__ __volatile__("outw %0, %1" : : "a"(data), "d"(port));
}

void io_wait() { outb(0x80, 0); }

void wait(u32 ticks) {
    unsigned long eticks;

    eticks = timer_ticks + ticks;
    while ((unsigned long)timer_ticks < eticks)
        ;
}

#define BUFFER_SIZE 256

str read_line(str prompt) {
    init_keyboard();
    static char buffer[BUFFER_SIZE];
    char *ptr = buffer;
    char *buffer_end = buffer + sizeof(buffer) - 1;

    write(prompt);

    while (true) {
        if (last_scancode == 0x00) {
            continue;
        }

        unsigned char c = layout[last_scancode];

        if (shift) {
            c = layout_shift[last_scancode];
        }

        if (c == '\n') {
            write_char(c);
            *ptr = '\0';
            disable_keyboard();
            last_scancode = 0;
            return buffer;
        } else if (c == '\b') {
            if (ptr > buffer) {
                ptr--;
                write_char(c);
            }
        } else if (last_scancode == 0x4B) { // Left arrow
            if (csr_x > 0) {
                csr_x--;
                move_csr();
            }
        } else if (last_scancode == 0x4D) { // Right arrow
            if (csr_x < 79) {
                csr_x++;
                move_csr();
            }
        } else if (c >= ' ' && ptr < buffer_end) {
            *ptr++ = c;
            write_char(c);
        } else if (c == '\t') {
            for (int i = TAB_WIDTH; i > 0; i--) {
                if (ptr < buffer_end) {
                    *ptr++ = ' ';
                }
            }
            write_char('\t');
        }
        last_scancode = 0;
    }
}

str read_line_buffered(str prompt, u32 buffer_size) {
    // TODO: Impelement paging to be possible to malloc
    return "";
}

void write_hex(unsigned int value) {
    int tmp;

    write("0x");

    char noZeroes = 1;

    int i;
    for (i = 28; i > 0; i -= 4) {
        tmp = (value >> i) & 0x0F;
        if (tmp == 0 && noZeroes != 0) {
            continue;
        }

        if (tmp >= 0xA) {
            noZeroes = 0;
            write_char(tmp - 0xA + 'a');
        } else {
            noZeroes = 0;
            write_char(tmp + '0');
        }
    }

    tmp = value & 0x0F;
    if (tmp >= 0xA) {
        write_char(tmp - 0xA + 'a');
    } else {
        write_char(tmp + '0');
    }
}

int strncmp(const str s1, const str s2, size n) {
    for (size i = 0; i < n; i++) {
        if (s1[i] != s2[i] || s1[i] == '\0' || s2[i] == '\0') {
            return (unsigned char)s1[i] - (unsigned char)s2[i];
        }
    }
    return 0;
}

void list_dir(const str path) { fat32_list_path(path); }

void tolower(str s) {
    for (size i = 0; s[i] != '\0'; i++) {
        if (s[i] >= 'A' && s[i] <= 'Z') {
            s[i] += 32;
        }
    }
}

void toupper(str s) {
    for (size i = 0; s[i] != '\0'; i++) {
        if (s[i] >= 'a' && s[i] <= 'z') {
            s[i] -= 32;
        }
    }
}

void trim(str s) {
    size i = 0;
    size j = strlen(s) - 1;

    while (s[i] == ' ' || s[i] == '\t' || s[i] == '\n') {
        i++;
    }

    while (s[j] == ' ' || s[j] == '\t' || s[j] == '\n') {
        j--;
    }

    if (i > j) {
        s[0] = '\0';
        return;
    }

    for (size k = 0; k <= j - i; k++) {
        s[k] = s[k + i];
    }

    s[j - i + 1] = '\0';
}

str concat(const str s1, const str s2) {
    size len1 = strlen(s1);
    size len2 = strlen(s2);

    str result = (str)malloc(len1 + len2 + 1);
    if (result == NULL) {
        return NULL;
    }

    for (size i = 0; i < len1; i++) {
        result[i] = s1[i];
    }

    for (size i = 0; i < len2; i++) {
        result[len1 + i] = s2[i];
    }

    result[len1 + len2] = '\0';

    return result;
}

bool dir_exists(const str path) {
    u32 cluster = fat32_find_cluster(path);
    return cluster != 0xFFFFFFFF;
}

bool file_exists(const str path) {
    u32 cluster = fat32_find_cluster(path);
    return cluster != 0xFFFFFFFF;
}

str read_file(const str path) {
    str content = fat32_read_file(path);
    if (content == NULL) {
        write("ERROR: File not found\n");
        return NULL;
    }
    return content;
}

bool create_dir(const str path) {
    u32 cluster = fat32_create_directory(path);
    return cluster != 0xFFFFFFFF;
}

str strchr(str s, int c) {
    for (size i = 0; s[i] != '\0'; i++) {
        if (s[i] == c) {
            return s + i;
        }
    }
    return NULL;
}

str strncpy(str dest, const str src, size count) {
    size i;

    for (i = 0; i < count && src[i] != '\0'; i++) {
        dest[i] = src[i];
    }

    if (i < count) {
        dest[i] = '\0';
    }

    return dest;
}

bool ends_with(const str s, char c) {
    size len = strlen(s);
    return len > 0 && s[len - 1] == c;
}

bool contains(const str s, char c) {
    for (size i = 0; s[i] != '\0'; i++) {
        if (s[i] == c) {
            return true;
        }
    }
    return false;
}

int strfind(const str s, char c) {
    for (size i = 0; s[i] != '\0'; i++) {
        if (s[i] == c) {
            return i;
        }
    }
    return -1;
}
