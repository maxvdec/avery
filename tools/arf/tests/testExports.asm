
extern space

section .data
    msg db "Hello, ARF!", 0x0
    len equ $ - msg

section .text
    global start

start:
    mov eax, 1 ; syscall number for write
    mov ebx, 1
    mov ecx, msg
    mov edx, len
    int 0x80

    call space
    jmp $