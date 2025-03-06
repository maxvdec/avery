/*
 irq.h
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: IRQ definitions
 Copyright (c) 2025 Maxims Enterprise
*/

#ifndef _IRQ_H
#define _IRQ_H

#include "system/isr.h"

extern void _irq0();
extern void _irq1();
extern void _irq2();
extern void _irq3();
extern void _irq4();
extern void _irq5();
extern void _irq6();
extern void _irq7();
extern void _irq8();
extern void _irq9();
extern void _irq10();
extern void _irq11();
extern void _irq12();
extern void _irq13();
extern void _irq14();
extern void _irq15();

extern void *irq_routines[16];

void irq_install_handler(int irq, void (*handler)(struct regs *r));
void irq_uninstall_handler(int irq);
void remap_irqs();
void init_irqs();
void irq_handler(struct regs *r);

#endif // _IRQ_H
