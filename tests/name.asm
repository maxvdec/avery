section .data
    welcome_msg db "Welcome to this program!", 10, 0
    ask_name_msg db "What's your name? > ", 0 
    hello_prefix db "Hello, ", 0

section .bss
    name resb 64

section .text
    global main
    
main:
    mov eax, 1 
    mov ebx, 1
    mov ecx, welcome_msg
    mov edx, 26
    int 0x80
    
    mov eax, 1 
    mov ebx, 1 
    mov ecx, ask_name_msg
    mov edx, 20
    int 0x80
    
    mov eax, 0 
    mov ebx, 0 
    mov ecx, name
    mov edx, 64
    int 0x80
    
    mov eax, 1 
    mov ebx, 1 
    mov ecx, hello_prefix
    mov edx, 7
    int 0x80
    
    mov eax, 1 
    mov ebx, 1 
    mov ecx, name
    mov edx, esi
    int 0x80
    
    mov eax, 0x05
    xor ebx, ebx
    int 0x80
