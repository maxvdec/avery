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
    
    mov eax, [esp + 28]   
    mov ebx, [esp + 16]   
    mov ecx, [esp + 24]   
    mov edx, [esp + 20]   
    mov esi, [esp + 4]    
    mov edi, [esp + 0]    
    
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
    pop gs
    pop fs  
    pop es
    pop ds
    
    iretd