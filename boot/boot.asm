global _start
extern kernel_main

section .multiboot2
align 8
multiboot2_start:
dd 0xe85250d6
dd 0x00
dd multiboot2_end - multiboot2_start
dd - (0xe85250d6 + 0x00 + (multiboot2_end - multiboot2_start))

align 8
dw 0
dw 0
dd 8

multiboot2_end:

section .bss
align 16
stack_bottom:
    resb 16384
stack_top:

section .text
_start:
    mov esp, stack_top
    push ebx
    push eax
    cli
    call kernel_main
    cli
    hlt
