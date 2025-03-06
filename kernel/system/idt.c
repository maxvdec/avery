/*
 idt.c
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: IDT implementation
 Copyright (c) 2025 Maxims Enterprise
*/

#include "system/idt.h"

struct idt_entry idt[256];
struct idt_ptr idtp;

void idt_set_gate(u8 num, u32 base, u16 sel, u8 flags) {
    idt[num].base_lo = base & 0xFFFF;
    idt[num].base_hi = (base >> 16) & 0xFFFF;

    idt[num].sel = sel;
    idt[num].always0 = 0;
    idt[num].flags = flags;
}

void init_idt() {
    idtp.limit = (sizeof(struct idt_entry) * 256) - 1;
    idtp.base = (u32)&idt;

    memset((u8 *)&idt, 0, sizeof(struct idt_entry) * 256);

    load_idt();
}
