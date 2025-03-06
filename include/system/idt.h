/*
 idt.h
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: IDT definition and linking with assembly
 Copyright (c) 2025 Maxims Enterprise
*/

#ifndef _IDT_H
#define _IDT_H

#include "common.h"

struct idt_entry {
    u16 base_lo;
    u16 sel;
    u8 always0;
    u8 flags;
    u16 base_hi;
} __attribute__((packed));

struct idt_ptr {
    u16 limit;
    u32 base;
} __attribute__((packed));

extern struct idt_entry idt[256];
extern struct idt_ptr idtp;

void init_idt();
void idt_set_gate(u8 num, u32 base, u16 sel, u8 flags);
extern void load_idt();

#endif // _IDT_H
