/*
 keyboard.c
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: Keyboard driver
 Copyright (c) 2025 Maxims Enterprise
*/

#include "drivers/keyboard.h"
#include "common.h"
#include "system/irq.h"
#include "vga.h"

unsigned char kbdus[128] = {
    0,    27,  '1', '2', '3',  '4', '5', '6', '7',  '8', /* 9 */
    '9',  '0', '-', '=', '\b',                           /* Backspace */
    '\t',                                                /* Tab */
    'q',  'w', 'e', 'r',                                 /* 19 */
    't',  'y', 'u', 'i', 'o',  'p', '[', ']', '\n',      /* Enter key */
    0,                                                   /* 29   - Control */
    'a',  's', 'd', 'f', 'g',  'h', 'j', 'k', 'l',  ';', /* 39 */
    '\'', '`', 0,                                        /* Left shift */
    '\\', 'z', 'x', 'c', 'v',  'b', 'n',                 /* 49 */
    'm',  ',', '.', '/', 0,                              /* Right shift */
    '*',  0,                                             /* Alt */
    ' ',                                                 /* Space bar */
    0,                                                   /* Caps lock */
    0,                                                   /* 59 - F1 key ... > */
    0,    0,   0,   0,   0,    0,   0,   0,   0,         /* < ... F10 */
    0,                                                   /* 69 - Num lock*/
    0,                                                   /* Scroll Lock */
    0,                                                   /* Home key */
    0,                                                   /* Up Arrow */
    0,                                                   /* Page Up */
    '-',  0,                                             /* Left Arrow */
    0,    0,                                             /* Right Arrow */
    '+',  0,                                             /* 79 - End key*/
    0,                                                   /* Down Arrow */
    0,                                                   /* Page Down */
    0,                                                   /* Insert Key */
    0,                                                   /* Delete Key */
    0,    0,   0,   0,                                   /* F11 Key */
    0,                                                   /* F12 Key */
    0, /* All other keys are undefined */
};

unsigned char kbdes[128] = {
    0,    27,   '1',  '2',  '3',  '4', '5', '6', '7',  '8', /* 9 */
    '9',  '0',  '\'', 0xA1, '\b', /* Backspace ('¡' = 0xA1) */
    '\t',                         /* Tab */
    'q',  'w',  'e',  'r',        /* 19 */
    't',  'y',  'u',  'i',  'o',  'p', '`', '+', '\n',       /* Enter key */
    0,                                                       /* 29 - Control */
    'a',  's',  'd',  'f',  'g',  'h', 'j', 'k', 'l',  0xF1, /* 'ñ' = 0xF1 */
    '\'', 0xBA, 0,                          /* Left shift ('º' = 0xBA) */
    0xE7, 'z',  'x',  'c',  'v',  'b', 'n', /* 49 ('ç' = 0xE7) */
    'm',  ',',  '.',  '-',  0,              /* Right shift */
    '*',  0,                                /* Alt */
    ' ',                                    /* Space bar */
    0,                                      /* Caps lock */
    0,    0,    0,    0,    0,    0,   0,   0,   0, /* F1-F10 */
    0,                                              /* 69 - Num lock*/
    0,                                              /* Scroll Lock */
    0,                                              /* Home key */
    0,                                              /* Up Arrow */
    0,                                              /* Page Up */
    '-',  0,                                        /* Left Arrow */
    0,    0,                                        /* Right Arrow */
    '+',  0,                                        /* 79 - End key */
    0,                                              /* Down Arrow */
    0,                                              /* Page Down */
    0,                                              /* Insert Key */
    0,                                              /* Delete Key */
    0,    0,    0,    0,                            /* F11 Key */
    0,                                              /* F12 Key */
    0,
};

unsigned char kbdes_shift[128] = {
    0,    27,   '!', '"',  '#',  '$', '%', '&', '/',  '(', /* 9 */
    ')',  '=',  '?', 0xA1, '\b', /* Backspace ('¡' = 0xA1) */
    '\t',                        /* Tab */
    'Q',  'W',  'E', 'R',        /* 19 */
    'T',  'Y',  'U', 'I',  'O',  'P', '~', '*', '\n',       /* Enter key */
    0,                                                      /* 29 - Control */
    'A',  'S',  'D', 'F',  'G',  'H', 'J', 'K', 'L',  0xF1, /* 'Ñ' = 0xF1 */
    '"',  0xBA, 0,                                 /* Left shift ('º' = 0xBA) */
    0xE7, 'Z',  'X', 'C',  'V',  'B', 'N',         /* 49 ('Ç' = 0xE7) */
    'M',  '<',  '>', '_',  0,                      /* Right shift */
    '*',  0,                                       /* Alt */
    ' ',                                           /* Space bar */
    0,                                             /* Caps lock */
    0,    0,    0,   0,    0,    0,   0,   0,   0, /* F1-F10 */
    0,                                             /* 69 - Num lock*/
    0,                                             /* Scroll Lock */
    0,                                             /* Home key */
    0,                                             /* Up Arrow */
    0,                                             /* Page Up */
    '-',  0,                                       /* Left Arrow */
    0,    0,                                       /* Right Arrow */
    '+',  0,                                       /* 79 - End key */
    0,                                             /* Down Arrow */
    0,                                             /* Page Down */
    0,                                             /* Insert Key */
    0,                                             /* Delete Key */
    0,    0,    0,   0,                            /* F11 Key */
    0,                                             /* F12 Key */
    0,
};

unsigned char *layout = kbdes; // TODO: Change this on production
unsigned char *layout_shift = kbdes_shift;

bool shift = false;

void init_keyboard() { irq_install_handler(1, keyboard_handler); }
void disable_keyboard() { irq_uninstall_handler(1); }

volatile u8 last_scancode = 0x00;

void keyboard_handler(struct regs *_) {
    u8 scancode = inb(0x60);
    if (scancode & 0x80) {
        if (scancode == 0xAA || scancode == 0xB6) {
            shift = false;
        }
    } else {
        if (scancode == 0x2A || scancode == 0x36) {
            shift = true;
        }

        last_scancode = scancode;
    }
}
