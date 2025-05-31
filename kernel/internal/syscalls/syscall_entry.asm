section .text
global int80_handler
extern syscall_handler

int80_handler:
    pusha

    mov eax, [esp + 28]  ; EAX (syscall number)
    mov ebx, [esp + 16]  ; EBX (arg1)
    mov ecx, [esp + 24]  ; ECX (arg2)  
    mov edx, [esp + 20]  ; EDX (arg3)
    mov esi, [esp + 4]   ; ESI (arg4)
    mov edi, [esp + 0]   ; EDI (arg5)
    
    push edi    
    push esi    
    push edx    
    push ecx    
    push ebx    
    push eax    
    
    call syscall_handler
    add esp, 24  
    
    mov [esp + 28], eax
    
    popa
    iretd