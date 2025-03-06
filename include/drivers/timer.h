/*
 timer.h
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: Simple PIT 8253/8254 System Clock driver
 Copyright (c) 2025 Maxims Enterprise
*/

#ifndef _TIMER_H
#define _TIMER_H

#include "system/isr.h"

#define TIMER_FREQ 1193180

void timer_phase(int hz);
extern int timer_ticks;
void timer_handler(struct regs *r);
void init_timer();

#endif // _TIMER_H
