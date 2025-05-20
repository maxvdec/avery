#!/bin/bash

hdiutil create -size 64m -fs FAT32 -volname AVKERNEL disk
hdiutil convert disk.dmg -format UDRW -o disk.img
cp disk.img.dmg disk.img
rm disk.dmg