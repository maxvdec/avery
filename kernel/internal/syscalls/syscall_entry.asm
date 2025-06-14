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
    
    ; ESP + 0:  EDI (from pusha)
    ; ESP + 4:  ESI  
    ; ESP + 8:  EBP
    ; ESP + 12: ESP (original)
    ; ESP + 16: EBX
    ; ESP + 20: EDX  
    ; ESP + 24: ECX
    ; ESP + 28: EAX
    ; ESP + 32: GS (from our pushes)
    ; ESP + 36: FS
    ; ESP + 40: ES
    ; ESP + 44: DS
    ; ESP + 48: EIP (from interrupt)
    ; ESP + 52: CS
    ; ESP + 56: EFLAGS
    ; ESP + 60: User ESP (if privilege change)
    ; ESP + 64: User SS (if privilege change)
    
    ; Load registers from correct stack positions
    mov eax, [esp + 28]   ; EAX - syscall number
    mov ebx, [esp + 16]   ; EBX - arg1
    mov ecx, [esp + 24]   ; ECX - arg2  
    mov edx, [esp + 20]   ; EDX - arg3
    mov esi, [esp + 4]    ; ESI - arg4
    mov edi, [esp + 0]    ; EDI - arg5
    
    ; Push in REVERSE order for C calling convention
    ; (last parameter pushed first)
    push edi              ; arg5 (EDI)
    push esi              ; arg4 (ESI)  
    push edx              ; arg3 (EDX)
    push ecx              ; arg2 (ECX)
    push ebx              ; arg1 (EBX)
    push eax              ; syscall_number (EAX)
    call syscall_handler
    add esp, 24           ; Clean up 6 parameters * 4 bytes each
    
    ; Store return value back to EAX on stack
    mov [esp + 28], eax  
    
    popa
    pop gs
    pop fs  
    pop es
    pop ds
    
    iretd