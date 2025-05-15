
global idt_load
extern idtPtr
idt_load:
    lidt [idtPtr]
    ret