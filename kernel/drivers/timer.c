/*
 timer.c
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: Standard PIT Driver
 Copyright (c) 2025 Maxims Enterprise
*/

#include "drivers/timer.h"
#include "common.h"
#include "system/irq.h"

int timer_ticks = 0;

void timer_phase(int hz) {
    int divisor = TIMER_FREQ / hz;
    outb(0x43, 0x36);
    outb(0x40, divisor & 0xFF);
    outb(0x40, divisor >> 8);
}

void timer_handler(struct regs *_) { timer_ticks++; }

void init_timer() {
    timer_phase(100);
    irq_install_handler(0, timer_handler);
}
