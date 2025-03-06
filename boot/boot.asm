
global _start
extern kernel_main

section .multiboot
align 4
dd 0x1BADB002
dd 0x00 
dd - (0x1BADB002 + 0x00)

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
    sti
    call kernel_main
    cli 
    hlt 

