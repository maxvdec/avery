global _start
extern kernel_main
extern stack_top

section .multiboot2
align 8
multiboot2_start:
dd 0xe85250d6
dd 0x00
dd multiboot2_end - multiboot2_start
dd - (0xe85250d6 + 0x00 + (multiboot2_end - multiboot2_start))

align 8
dd 5 
dd 20
dw 1
dw 0
dd 1920      
dd 1080      
dd 32        

align 8
dw 0
dw 0
dd 8

multiboot2_end:

section .text
_start:
    mov esp, stack_top

    push ebx
    push eax
    
    mov eax, cr0
    and eax, ~(1 << 2)  ; Clear CR0.EM (bit 2) - enable FPU emulation off
    or eax, (1 << 1)    ; Set CR0.MP (bit 1) - enable FPU monitoring
    and eax, ~(1 << 3)  ; Clear CR0.TS (bit 3) - clear task switched flag
    mov cr0, eax
    
    fninit ; Initialize the FPU
    
    mov eax, 1
    cpuid
    test edx, (1 << 25) ; Check SSE support bit
    jz no_sse
    test edx, (1 << 26) ; Check SSE2 support bit  
    jz no_sse

    mov eax, cr4
    or eax, (1 << 9)    ; Set CR4.OSFXSR (bit 9) - enable SSE
    or eax, (1 << 10)   ; Set CR4.OSXMMEXCPT (bit 10) - enable SSE exceptions
    mov cr4, eax
    
    cli
    call kernel_main
    
no_sse:
    cli
    jmp .hang

.hang:
    hlt
    jmp .hang