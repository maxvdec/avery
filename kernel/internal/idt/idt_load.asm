global idt_load
extern get_idt_ptr 
idt_load:
    push ebp
    mov ebp, esp
    call get_idt_ptr    
    lidt [eax]          
    mov esp, ebp
    pop ebp             
    ret