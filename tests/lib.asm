
global sayhello
section .text
sayhello:
    mov eax, 1
    mov ebx, 1
    mov ecx, hello
    mov edx, hello_len
    int 0x80

    ret

section .data
hello db 'Hello, World!', 0xA
hello_len equ $ - hello