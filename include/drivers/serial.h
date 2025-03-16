/*
 serial.h
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: Serial transmission through COM1 driver
 Copyright (c) 2025 Maxims Enterprise
*/

#ifndef _SERIAL_H
#define _SERIAL_H

#include "common.h"
#define SERIAL_PORT_COM1 0x3F8

void serial_init();
u32 is_serial_read();
void serial_write(char data);
void serial_write_str(char *data);

#endif // _SERIAL_H
