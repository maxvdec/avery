#!/bin/bash

qemu-img create -f raw disk.img 64M
mkfs.fat -F 32 disk.img
