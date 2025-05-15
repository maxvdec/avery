global gdt_flush
extern get_gdt_ptr

gdt_flush:
    push ebp
    mov ebp, esp
    
    call get_gdt_ptr
    lgdt [eax]
    
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    jmp 0x08:flush2
flush2:
    pop ebp
    ret