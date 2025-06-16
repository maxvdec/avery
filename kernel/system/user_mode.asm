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
    
    mov eax, [esp + 4]             ; eax = current context pointer
    
    mov [eax + 0], eax             ; save eax (will be overwritten below)
    mov [eax + 4], ebx             ; save ebx
    mov [eax + 8], ecx             ; save ecx
    mov [eax + 12], edx            ; save edx
    mov [eax + 16], esi            ; save esi
    mov [eax + 20], edi            ; save edi
    mov [eax + 24], ebp            ; save ebp
    
    lea ebx, [esp + 12]            ; ebx = original esp (before call + 2 params)
    mov [eax + 28], ebx            ; save original esp
    
    mov ebx, [esp]                 ; ebx = return address
    mov [eax + 32], ebx            ; save eip
    
    pushfd
    pop ebx
    mov [eax + 36], ebx            ; save eflags
    
    mov bx, ds
    mov [eax + 40], bx             ; save ds
    mov bx, es  
    mov [eax + 42], bx             ; save es
    mov bx, fs
    mov [eax + 44], bx             ; save fs
    mov bx, gs
    mov [eax + 46], bx             ; save gs
    mov bx, ss
    mov [eax + 48], bx             ; save ss
    mov bx, cs
    mov [eax + 50], bx             ; save cs
    
    mov ebx, cr3
    mov [eax + 52], ebx            ; save cr3
    
    ; Get next context pointer
    mov eax, [esp + 8]             ; eax = next context pointer
    
    mov ebx, cr3                   ; get current CR3
    mov ecx, [eax + 52]            ; get next CR3
    cmp ebx, ecx                   ; compare page directories
    je skip_cr3_switch             ; skip if same page directory
    
    mov cr3, ecx                   ; load new page directory
    
skip_cr3_switch:
    mov ebx, [eax + 36]            ; next eflags
    mov ecx, [eax + 32]            ; next eip  
    mov dx, [eax + 50]             ; next cs
    mov esi, [eax + 28]            ; next esp
    
    mov esp, esi                   ; switch to next context's stack
    
    push ebx                       ; push eflags for iret
    push edx                       ; push cs for iret (zero-extended)
    push ecx                       ; push eip for iret
    
    mov cx, [eax + 40]             ; restore ds
    mov ds, cx
    mov cx, [eax + 42]             ; restore es
    mov es, cx
    mov cx, [eax + 44]             ; restore fs
    mov fs, cx
    mov cx, [eax + 46]             ; restore gs
    mov gs, cx
    
    mov ebx, [eax + 4]             ; restore ebx
    mov ecx, [eax + 8]             ; restore ecx  
    mov edx, [eax + 12]            ; restore edx
    mov esi, [eax + 16]            ; restore esi
    mov edi, [eax + 20]            ; restore edi
    mov ebp, [eax + 24]            ; restore ebp
    
    mov eax, [eax + 0]             ; restore eax
    
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