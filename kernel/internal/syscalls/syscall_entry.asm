global int80_handler
extern syscall_handler
int80_handler:
    ; Save segment registers
    push ds
    push es  
    push fs
    push gs
    
    ; Save all general purpose registers FIRST
    pusha
    
    ; NOW set up kernel data segments (after saving registers)
    mov ax, 0x10          ; Kernel data segment
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    
    ; Load syscall arguments (EAX is now safely stored on stack)
    mov eax, [esp + 28]   ; EAX - syscall number
    mov ebx, [esp + 16]   ; EBX - arg1
    mov ecx, [esp + 24]   ; ECX - arg2
    mov edx, [esp + 20]   ; EDX - arg3
    mov esi, [esp + 4]    ; ESI - arg4
    mov edi, [esp + 0]    ; EDI - arg5
    
    ; Call the C syscall handler
    push edi              ; arg5
    push esi              ; arg4
    push edx              ; arg3
    push ecx              ; arg2
    push ebx              ; arg1
    push eax              ; syscall number
    
    call syscall_handler
    add esp, 24           ; Clean up stack (6 parameters * 4 bytes)
    
    ; Store return value back in EAX position on stack
    mov [esp + 28], eax   
    
    ; Restore all registers
    popa
    pop gs
    pop fs
    pop es
    pop ds
    
    ; Return to user mode
    iretd