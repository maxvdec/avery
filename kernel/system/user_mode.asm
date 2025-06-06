global switch_to_user_mode
switch_to_user_mode:
    ; esp + 4  -> eax
    ; esp + 8  -> ebx  
    ; esp + 12 -> ecx
    ; esp + 16 -> edx
    ; esp + 20 -> esi
    ; esp + 24 -> edi
    ; esp + 28 -> ebp
    ; esp + 32 -> esp (stack) 
    ; esp + 36 -> eip
    ; esp + 40 -> eflags
    ; esp + 44 -> cs
    ; esp + 48 -> ds
    ; esp + 52 -> es
    ; esp + 56 -> fs
    ; esp + 60 -> gs
    ; esp + 64 -> ss
    ; esp + 68 -> page_dir
    
    mov eax, [esp + 64]   
    mov ebx, [esp + 32]   
    mov ecx, [esp + 40]   
    mov edx, [esp + 44]   
    mov esi, [esp + 36]   
    
    push eax              
    push ebx              
    push ecx              
    push edx              
    push esi              
    
    mov ax, [esp + 68]
    mov ds, ax
    mov ax, [esp + 72]
    mov es, ax
    mov ax, [esp + 76]
    mov fs, ax
    mov ax, [esp + 80] 
    mov gs, ax
    
    mov eax, [esp + 88]   
    mov cr3, eax          
    
    mov eax, [esp + 24]
    mov ebx, [esp + 28]
    mov ecx, [esp + 32]
    mov edx, [esp + 36]
    mov esi, [esp + 40]
    mov edi, [esp + 44]
    mov ebp, [esp + 48]
    
    iret