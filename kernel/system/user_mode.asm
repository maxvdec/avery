global switch_to_user_mode
switch_to_user_mode:
    ; Stack layout when called:
    ; esp + 4  -> eax
    ; esp + 8  -> ebx  
    ; esp + 12 -> ecx
    ; esp + 16 -> edx
    ; esp + 20 -> esi
    ; esp + 24 -> edi
    ; esp + 28 -> ebp
    ; esp + 32 -> esp (user stack) 
    ; esp + 36 -> eip
    ; esp + 40 -> eflags
    ; esp + 44 -> cs
    ; esp + 48 -> ds
    ; esp + 52 -> es
    ; esp + 56 -> fs
    ; esp + 60 -> gs
    ; esp + 64 -> ss
    ; esp + 68 -> page_dir
    
    cli
    
    mov eax, esp
    
    mov ebx, [eax + 68]   
    test ebx, ebx         
    jz .error             
    mov cr3, ebx
    
    mov ebx, [eax + 64]   ; ss
    push ebx
    
    mov ebx, [eax + 32]   ; user esp
    push ebx
    
    mov ebx, [eax + 40]   ; eflags
    or ebx, 0x200         ; Set IF flag
    push ebx
    
    mov ebx, [eax + 44]   ; cs
    push ebx
    
    mov ebx, [eax + 36]   ; eip
    push ebx
    
    mov bx, [eax + 48]    ; ds
    mov ds, bx
    mov bx, [eax + 52]    ; es
    mov es, bx
    mov bx, [eax + 56]    ; fs
    mov fs, bx
    mov bx, [eax + 60]    ; gs
    mov gs, bx
    
    mov ebx, [eax + 8]    ; ebx
    mov ecx, [eax + 12]   ; ecx  
    mov edx, [eax + 16]   ; edx
    mov esi, [eax + 20]   ; esi
    mov edi, [eax + 24]   ; edi
    mov ebp, [eax + 28]   ; ebp
    mov eax, [eax + 4]    ; eax
    
    iret

.error:
    sti
    ret