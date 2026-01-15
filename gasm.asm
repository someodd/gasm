; =============================================================================
; GASM (Gopher Assembly) - i386 Edition (v5.2)
;
; Fixes:    Fixed ESI Register Corruption (Segfault on loop).
;           Fixed possible d_reclen infinite loop.
;
; Build:    nasm -f elf32 gasm.asm -o gasm.o
; Link:     ld -m elf_i386 gasm.o -o gasm
; =============================================================================

section .data
    port_w      equ 0xD21E      ; Port 7890

    ; Null-terminated strings
    tab         db 0x09, 0
    crlf        db 0x0D, 0x0A, 0
    end_of_menu db ".", 0x0D, 0x0A, 0
    slash       db "/", 0
    host_str    db "localhost", 0
    port_str    db "7890", 0
    err_msg     db "3Error", 0x09, "err", 0x09, "0", 0x0D, 0x0A, 0

    MAX_BASE_LEN equ 3000

section .bss
    ; Global State
    sockfd      resd 1
    clientfd    resd 1
    base_dir    resd 1          ; <--- NEW: Store Base Dir Ptr here
    
    ; Buffers
    req_buf     resb 512
    path_buf    resb 4096
    dent_buf    resb 4096
    file_buf    resb 4096
    stat_buf    resb 144
    args        resd 6

section .text
    global _start

_start:
    ; --- 1. Argument Parsing ---
    pop eax                 ; argc
    cmp eax, 2
    jl exit_app
    
    pop ebx                 ; argv[0]
    pop esi                 ; argv[1] (Base Path)

    ; Save Base Path to Global (Critical Fix)
    mov [base_dir], esi

    ; Validate Length
    mov edi, esi
    call strlen
    cmp eax, MAX_BASE_LEN
    jg exit_app

    ; --- 2. Socket ---
    mov dword [args], 2
    mov dword [args+4], 1
    mov dword [args+8], 0
    
    mov eax, 102            ; sys_socketcall
    mov ebx, 1              ; SYS_SOCKET
    mov ecx, args
    int 0x80
    test eax, eax
    js exit_app
    mov [sockfd], eax

    ; --- 3. Set SO_REUSEADDR ---
    mov eax, [sockfd]
    mov [args], eax
    mov dword [args+4], 1
    mov dword [args+8], 2
    push dword 1
    mov eax, esp
    mov [args+12], eax
    mov dword [args+16], 4
    
    mov eax, 102
    mov ebx, 14
    mov ecx, args
    int 0x80
    add esp, 4

    ; --- 4. Bind ---
    xor eax, eax
    push eax
    push eax
    mov word [esp], 2
    mov word [esp+2], port_w
    
    mov eax, [sockfd]
    mov [args], eax
    mov [args+4], esp
    mov dword [args+8], 16
    
    mov eax, 102
    mov ebx, 2
    mov ecx, args
    int 0x80
    add esp, 16
    test eax, eax
    js exit_app

    ; --- 5. Listen ---
    mov eax, [sockfd]
    mov [args], eax
    mov dword [args+4], 10
    mov eax, 102
    mov ebx, 4
    mov ecx, args
    int 0x80

server_loop:
    ; --- 6. Accept ---
    mov eax, [sockfd]
    mov [args], eax
    mov dword [args+4], 0
    mov dword [args+8], 0
    mov eax, 102
    mov ebx, 5
    mov ecx, args
    int 0x80
    test eax, eax
    js server_loop
    mov [clientfd], eax

    ; --- 7. Read ---
    mov eax, 3
    mov ebx, [clientfd]
    mov ecx, req_buf
    mov edx, 511
    int 0x80
    test eax, eax
    jle close_client

    ; --- 8. Sanitize ---
    mov ecx, eax
    mov edi, req_buf
.scan:
    cmp byte [edi], 0x0D
    je .term
    cmp byte [edi], 0x0A
    je .term
    inc edi
    loop .scan
.term:
    mov byte [edi], 0

    ; --- 9. Traversal Check ---
    mov edi, req_buf
    call check_traversal
    cmp eax, 1
    je send_error

    ; --- 10. Build Path ---
    ; FIX: Load from global [base_dir] instead of ESI
    mov edi, path_buf
    push dword [base_dir]   ; Source
    push edi                ; Dest
    call strcpy
    add esp, 8
    
    mov edi, path_buf
    call strlen_fast
    mov byte [edi], '/'
    inc edi
    
    push req_buf
    push edi
    call strcpy
    add esp, 8

    ; --- 11. Stat ---
    mov eax, 195            ; sys_stat64
    mov ebx, path_buf
    mov ecx, stat_buf
    int 0x80
    test eax, eax
    js send_error

    mov ax, [stat_buf + 16] ; st_mode
    and ax, 0xF000
    cmp ax, 0x4000
    je handle_dir
    jmp handle_file

; =============================================================================
; Directory Logic
; =============================================================================
handle_dir:
    mov eax, 5
    mov ebx, path_buf
    mov ecx, 0x10000
    mov edx, 0
    int 0x80
    test eax, eax
    js send_error
    mov esi, eax            ; ESI = Dir FD (Safe now, we don't need base_dir in reg)

.read_loop:
    mov eax, 220            ; sys_getdents64
    mov ebx, esi
    mov ecx, dent_buf
    mov edx, 4096
    int 0x80
    test eax, eax
    jle .done

    mov ebx, eax            ; Count
    xor edi, edi            ; Offset

.process:
    cmp edi, ebx
    jge .read_loop

    mov edx, dent_buf
    add edx, edi            ; EDX = Entry Pointer

    ; Filter '.'
    mov al, [edx + 19]
    cmp al, '.'
    je .next

    ; Type
    mov al, [edx + 18]
    cmp al, 4
    je .is_dir
    
    lea eax, [edx + 19]
    call check_txt
    test eax, eax
    jnz .is_txt
    
    mov al, '9'
    jmp .send
.is_dir:
    mov al, '1'
    jmp .send
.is_txt:
    mov al, '0'

.send:
    mov [file_buf], al
    call send_byte

    lea eax, [edx + 19]
    call send_str

    mov eax, tab
    call send_1byte
    mov eax, slash
    call send_1byte

    cmp byte [req_buf], 0
    je .no_prefix
    mov eax, req_buf
    call send_str
    mov eax, slash
    call send_1byte
.no_prefix:
    lea eax, [edx + 19]
    call send_str

    mov eax, tab
    call send_1byte
    mov eax, host_str
    call send_str
    mov eax, tab
    call send_1byte
    mov eax, port_str
    call send_str
    mov eax, crlf
    call send_str

.next:
    movzx eax, word [edx + 16] ; d_reclen
    test eax, eax           ; Safety: If reclen is 0, abort loop
    jz .read_loop           ; (Avoid infinite loop)
    add edi, eax
    jmp .process

.done:
    mov eax, 6
    mov ebx, esi
    int 0x80
    mov eax, end_of_menu
    call send_str
    jmp close_client

; =============================================================================
; File Logic
; =============================================================================
handle_file:
    mov eax, 5
    mov ebx, path_buf
    mov ecx, 0
    xor edx, edx
    int 0x80
    test eax, eax
    js send_error
    mov esi, eax

.stream:
    mov eax, 3
    mov ebx, esi
    mov ecx, file_buf
    mov edx, 4096
    int 0x80
    test eax, eax
    jle .close

    mov edx, eax
    mov eax, 4
    mov ebx, [clientfd]
    mov ecx, file_buf
    int 0x80
    jmp .stream

.close:
    mov eax, 6
    mov ebx, esi
    int 0x80
    jmp close_client

; =============================================================================
; Helpers
; =============================================================================
send_error:
    mov eax, err_msg
    call send_str
    jmp close_client

close_client:
    mov eax, 6
    mov ebx, [clientfd]
    int 0x80
    jmp server_loop

exit_app:
    mov eax, 1
    xor ebx, ebx
    int 0x80

strlen:
    xor eax, eax
    push edi
.L: cmp byte [edi], 0
    je .D
    inc edi
    inc eax
    jmp .L
.D: pop edi
    ret

strlen_fast:
.L: cmp byte [edi], 0
    je .D
    inc edi
    jmp .L
.D: ret

strcpy:
    push ebp
    mov ebp, esp
    push esi
    push edi
    mov edi, [ebp+8]
    mov esi, [ebp+12]
.loop:
    mov al, [esi]
    mov [edi], al
    test al, al
    jz .done
    inc esi
    inc edi
    jmp .loop
.done:
    pop edi
    pop esi
    pop ebp
    ret

check_traversal:
    push edi
.L: mov al, [edi]
    test al, al
    jz .ok
    cmp al, '.'
    je .dot
    inc edi
    jmp .L
.dot:
    mov al, [edi+1]
    cmp al, '.'
    je .bad
    inc edi
    jmp .L
.bad:
    pop edi
    mov eax, 1
    ret
.ok:
    pop edi
    xor eax, eax
    ret

check_txt:
    push edi
    mov edi, eax
    call strlen
    cmp eax, 4
    jl .no
    add edi, eax
    sub edi, 4
    mov eax, [edi]
    cmp eax, 0x7478742e
    je .y
.no:
    xor eax, eax
    pop edi
    ret
.y:
    mov eax, 1
    pop edi
    ret

send_str:
    push ebx
    push ecx
    push edx
    push edi
    
    mov edi, eax
    call strlen
    mov edx, eax
    mov ecx, edi
    
    mov eax, 4
    mov ebx, [clientfd]
    int 0x80
    
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

send_1byte:
    push ebx
    push ecx
    push edx
    mov ecx, eax
    mov edx, 1
    mov eax, 4
    mov ebx, [clientfd]
    int 0x80
    pop edx
    pop ecx
    pop ebx
    ret

send_byte:
    mov eax, file_buf
    call send_1byte
    ret
