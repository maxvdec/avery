
section .text
global main
main:
    mov eax, 1 ; syscall number for write
    mov ebx, 1
    mov ecx, msg
    mov edx, len
    int 0x80

    jmp $

section .data
msg db "Hello, Another process!", 0x0
len equ $ - msg