section .text
global int80_handler
extern syscall_handler

int80_handler:
    push ds
    push es
    push fs
    push gs

    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    pusha  

    mov eax, [esp + 32]  
    mov ebx, [esp + 36]  
    mov ecx, [esp + 40]  
    mov edx, [esp + 44]  
    mov esi, [esp + 48]  
    mov edi, [esp + 52]  

    push edi
    push esi
    push edx
    push ecx
    push ebx
    push eax

    call syscall_handler
    add esp, 24

    mov [esp + 32], eax  

    popa  

    pop gs
    pop fs
    pop es
    pop ds

    iretd
