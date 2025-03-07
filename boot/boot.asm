
global _start
extern kernel_main


section .multiboot2
align 8
header_start:
    dd 0xe85250d6         
    dd 0                   
    dd header_end - header_start 
    dd -(0xe85250d6 + 0 + (header_end - header_start)) 

    dw 0                   
    dw 0                   

    dw 0x00000003
    dw 32
    dd 0 

    dd 1920 
    dd 1080
    dd 7680
    dd 32
    dd 0
header_end:


section .bss 
align 16
stack_bottom: 
    resb 16384
stack_top:

section .text 
_start:
    
    and esp, 0xFFFFFFF0
    mov eax, ebx
    sti
    call kernel_main
    cli 
    hlt 

