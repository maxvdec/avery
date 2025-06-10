# The Avery Relocatable Format (ARF)
The Avery Relocatable Format is a format for executing relocatable instructions, meaning that it can be loaded in memory in any place, since it does not use any type of hard-coded addresses. It's a successor to ELF in its sense of simplicity and it's tailored for the Avery Kernel.

## Tooling
We offer tooling for dealing with ARF files, although it's a **one way** translation.<br>
* `arf something.elf` will transform an ELF file to ARF.
* `ald object1.o object2.o object3.o` will link objects into an ARF. (This second one is not implemented but we pretend to do it)

## The Header
The Header tells us about the most important parts of the executable:
```mermaid
---
title: "An ARF Header"
---
stateDiagram-v2
    s1 : We read the ARF Identification ID (6 bytes)
    s2 : We read the Architecture byte (1 byte)
    s3 : We read the Host Architecture byte (1 byte)
    s4 : We read the sections table
    s5 : We read the symbols table
    s6 : We read the libraries table
    s7 : We read the fix table

    s1 --> s2
    s2 --> s3
    s3 --> s4
    s4 --> s5
    s5 --> s6
    s6 --> s7
```

Let's dive in each of these points to help you create an ARF header reader.