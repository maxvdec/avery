global switch_to_user_mode
global switch_context
global get_context

extern printHex
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
    ; Inputs:
    ;   [esp + 4]  = pointer to current context
    ;   [esp + 8]  = pointer to next context
    
    mov edx, [esp + 4]             ; edx = current context pointer (use edx to avoid corruption)
    
    mov [edx + 0], eax             ; save eax
    mov [edx + 4], ebx             ; save ebx
    mov [edx + 8], ecx             ; save ecx
    mov eax, [esp + 4]             ; get original eax value (current context pointer)
    mov [edx + 0], eax             ; save the actual eax that was passed in
    mov [edx + 12], edx            ; save edx (but edx was our temp, so save original)
    
    mov ebx, [esp + 4]             ; ebx = current context pointer
    
    mov [ebx + 0], eax             ; save eax
    mov [ebx + 8], ecx             ; save ecx  
    mov [ebx + 12], edx            ; save edx
    mov [ebx + 16], esi            ; save esi
    mov [ebx + 20], edi            ; save edi
    mov [ebx + 24], ebp            ; save ebp
    mov [ebx + 4], ebx             ; save ebx (this overwrites our temp but that's ok)
    
    lea eax, [esp + 12]            ; eax = original esp (before call + 2 params)
    mov [ebx + 28], eax            ; save original esp
    
    mov eax, [esp]                 ; eax = return address
    mov [ebx + 32], eax            ; save eip
    
    pushfd
    pop eax
    mov [ebx + 36], eax            ; save eflags
    
    mov ax, ds
    mov [ebx + 40], ax             ; save ds (16-bit)
    mov ax, es  
    mov [ebx + 42], ax             ; save es
    mov ax, fs
    mov [ebx + 44], ax             ; save fs
    mov ax, gs
    mov [ebx + 46], ax             ; save gs
    mov ax, ss
    mov [ebx + 48], ax             ; save ss
    mov ax, cs
    mov [ebx + 50], ax             ; save cs
    
    mov eax, cr3
    mov [ebx + 52], eax            ; save cr3
    
    mov esi, [esp + 8]             ; esi = next context pointer
    
    mov eax, [esi + 52]            ; next cr3
    mov ebx, [esi + 28]            ; next esp
    mov ecx, [esi + 32]            ; next eip
    mov edx, [esi + 36]            ; next eflags
    
    mov edi, cr3                   ; current CR3
    cmp edi, eax                   ; compare with next CR3
    je skip_cr3_switch             ; skip if same page directory
    
    mov cr3, eax                   ; load new page directory
    
skip_cr3_switch:
    mov esp, ebx                   ; switch to next context's stack
    
    push edx                       ; push eflags
    
    movzx eax, word [esi + 50]     ; get cs (zero-extend 16->32)
    push eax                       ; push cs
    
    push ecx                       ; push eip
    
    mov ax, [esi + 40]             ; restore ds
    mov ds, ax
    mov ax, [esi + 42]             ; restore es
    mov es, ax
    mov ax, [esi + 44]             ; restore fs
    mov fs, ax
    mov ax, [esi + 46]             ; restore gs  
    mov gs, ax
    
    mov eax, [esi + 0]             ; restore eax
    mov ebx, [esi + 4]             ; restore ebx
    mov ecx, [esi + 8]             ; restore ecx
    mov edx, [esi + 12]            ; restore edx
    mov edi, [esi + 20]            ; restore edi
    mov ebp, [esi + 24]            ; restore ebp
    mov esi, [esi + 16]            ; restore esi (do this last since we need esi)
    
    iret                           ; jump to new context                  

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