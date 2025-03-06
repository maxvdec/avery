/*
 keyboard.h
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: Keyboard abstractions and functions
 Copyright (c) 2025 Maxims Enterprise
*/

#ifndef _KEYBOARD_H
#define _KEYBOARD_H

#include "system/isr.h"

extern unsigned char kbdus[128];
extern unsigned char kbdes[128];
extern unsigned char kbdes_shift[128];

extern unsigned char *layout;
extern unsigned char *layout_shift;

extern volatile u8 last_scancode;

extern bool shift;

void disable_keyboard();
void init_keyboard();
void keyboard_handler(struct regs *r);

#endif // _KEYBOARD_H
