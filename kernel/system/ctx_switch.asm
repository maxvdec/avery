global switch_to_user_mode
global get_context

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

global switch_context
switch_context:
    cli

    mov eax, [esp + 4] ; old_context pointer
    mov ebx, [esp + 8] ; new_context pointer

    test eax, eax
    jz .switch_to_new
    test edx, edx
    jz .restore_and_return

    mov [eax + 0], eax
    mov [eax + 4], ebx
    mov [eax + 8], ecx
    mov [eax + 12], edx
    mov [eax + 16], esi
    mov [eax + 20], edi
    mov [eax + 24], ebp

    mov [eax + 28], esp

    mov ebp, [esp]
    mov [eax + 32], ebx

    pushfd
    pop ebx
    mov [eax + 36], ebx  ; Save eflags

    mov bx, cs
    mov [eax + 40], bx   ; Save cs
    mov bx, ds
    mov [eax + 44], bx   ; Save ds
    mov bx, es
    mov [eax + 48], bx   ; Save es
    mov bx, fs
    mov [eax + 52], bx   ; Save fs
    mov bx, gs
    mov [eax + 56], bx   ; Save gs
    mov bx, ss
    mov [eax + 60], bx   ; Save ss

    mov ebx, cr3
    mov [eax + 64], ebx

    push eax
    mov eax, [esp + 8]
    mov ebx, [esp]
    mov [ebx + 0], eax
    pop eax

.switch_to_new:
    mov eax, edx

    cmp eax, 0x1000
    jb .restore_and_return

    mov ebx, [eax + 64]
    test ebx, ebx
    jz .skip_page_dir

    test ebx, 0xFFF
    jnz .skip_page_dir

    mov cr3, ebx

.skip_page_dir:
    mov ebx, [eax + 44]     ; Load DS
    mov ds, bx
    mov ebx, [eax + 48]     ; Load ES  
    mov es, bx
    mov ebx, [eax + 52]     ; Load FS
    mov fs, bx
    mov ebx, [eax + 56]     ; Load GS
    mov gs, bx
    mov ebx, [eax + 60]     ; Load SS
    mov ss, bx
    
    mov ebx, [eax + 4]      ; Restore EBX
    mov ecx, [eax + 8]      ; Restore ECX  
    mov edx, [eax + 12]     ; Restore EDX
    mov esi, [eax + 16]     ; Restore ESI
    mov edi, [eax + 20]     ; Restore EDI
    mov ebp, [eax + 24]     ; Restore EBP
    
    mov esp, [eax + 28]     ; Restore ESP
    
    mov ebx, [eax + 36]     ; Get EFLAGS
    push ebx
    popfd                   ; Restore EFLAGS
    
    push dword [eax + 40]   ; Push CS
    push dword [eax + 32]   ; Push EIP
    
    mov eax, [eax + 0]      ; Restore EAX (this must be last!)
    
    sti
    
    retf

.restore_and_return:
    sti
    ret


get_context:
    push ebp
    mov ebp, esp
    
    mov eax, [ebp + 8]    ; Get pointer to context structure
    
    mov [eax + 4], eax    ; Save original eax (before we modified it)
    pushfd                ; Push flags to stack
    pop ecx               ; Pop into ecx
    mov [eax + 40], ecx   ; Save eflags
    
    mov [eax + 8], ebx    ; Save ebx
    mov [eax + 12], ecx   ; Save ecx
    mov [eax + 16], edx   ; Save edx
    mov [eax + 20], esi   ; Save esi
    mov [eax + 24], edi   ; Save edi
    mov [eax + 28], ebp   ; Save ebp
    
    mov cx, ds
    mov [eax + 48], cx    ; Save ds
    mov cx, es
    mov [eax + 52], cx    ; Save es
    mov cx, fs
    mov [eax + 56], cx    ; Save fs
    mov cx, gs
    mov [eax + 60], cx    ; Save gs
    mov cx, ss
    mov [eax + 64], cx    ; Save ss
    
    lea ecx, [ebp + 8]    ; Calculate original esp before function call
    mov [eax + 32], ecx   ; Save esp
    
    mov ecx, [ebp + 4]    ; Get return address
    mov [eax + 36], ecx   ; Save eip
    
    mov cx, cs
    mov [eax + 44], cx    ; Save cs
    
    mov ecx, cr3
    mov [eax + 68], ecx   ; Save page directory
    
    pop ebp
    ret