/*
 gdt.h
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: GDT function definition
 Copyright (c) 2025 Maxims Enterprise
*/

#ifndef _GDT_H
#define _GDT_H

#include "common.h"

struct gdt_entry {
    u16 limit_low;
    u16 base_low;
    u8 base_middle;
    u8 access;
    u8 granularity;
    u8 base_high;
} __attribute__((packed));

struct gdt_ptr {
    u16 limit;
    u32 base;
} __attribute__((packed));

extern struct gdt_entry gdt[3];
extern struct gdt_ptr gp;

extern void gdt_flush();

void gdt_set_gate(int num, u32 base, u32 limit, u8 access, u8 gran);
void init_gdt();

#endif
