; ping.s - Example transient command for 6502/Pico W system
; Location: 6502/ca65/commands/ping/ping.s
;
; This command demonstrates the proper pattern for transient commands:
; 1. Proper zero page usage ($58-$5F only)
; 2. Communication with Pico via pico_send_request
; 3. Direct screen output (since shell doesn't auto-print responses)
; 4. Register preservation
; 5. Clear success/failure indicators

; ---------------------------------------------------------------------------
; External symbols from pico_lib.s
; ---------------------------------------------------------------------------
.import pico_send_request
.import CMD_ID, ARG_LEN, LAST_STATUS

; ---------------------------------------------------------------------------
; System calls (from eater.lbl)
; ---------------------------------------------------------------------------
OUTCH = $FFEF    ; Print character in A
CRLF  = $FED1    ; Print CR/LF pair

; ---------------------------------------------------------------------------
; Zero Page for Transient Commands - USE ONLY $58-$5F
; $50-$57 are RESERVED for the shell - DO NOT USE
; ---------------------------------------------------------------------------
; t_str_ptr1   = $5A  ; 2 bytes - String pointer 1 (unused here)
; t_str_ptr2   = $5C  ; 2 bytes - String pointer 2 (unused here)
; t_ptr_temp   = $5E  ; 2 bytes - Temporary pointer (unused here)

; ---------------------------------------------------------------------------
; HEADER - MUST be first (2-byte load address for RUN command)
; ---------------------------------------------------------------------------
.segment "HEADER"
    .word $0800        ; Load at $0800 (little-endian)

; ---------------------------------------------------------------------------
; CODE - Program starts here at $0800
; ---------------------------------------------------------------------------
.segment "CODE"

start:
    ; -----------------------------------------------------------------------
    ; ALWAYS preserve registers when entering a transient command
    ; The shell's state must be restored before returning
    ; -----------------------------------------------------------------------
    php              ; Save processor status
    pha              ; Save A
    txa              
    pha              ; Save X
    tya
    pha              ; Save Y
    
    ; -----------------------------------------------------------------------
    ; Send PING command to Pico
    ; Command format: CMD_ID = $01 (CMD_SYS_PING), ARG_LEN = 0
    ; -----------------------------------------------------------------------
    lda #$01
    sta CMD_ID
    lda #$00
    sta ARG_LEN
    
    jsr pico_send_request   ; Send command and wait for response
    
    ; -----------------------------------------------------------------------
    ; Check result and print appropriate message
    ; LAST_STATUS contains result from Pico ($00 = OK, non-zero = error)
    ; -----------------------------------------------------------------------
    lda LAST_STATUS
    bne @fail
    
    ; Success - print "PONG" followed by CR/LF
    lda #'P'
    jsr OUTCH
    lda #'O'
    jsr OUTCH
    lda #'N'
    jsr OUTCH
    lda #'G'
    jsr OUTCH
    jsr CRLF
    jmp @done
    
@fail:
    ; Failure - print "FAIL" followed by CR/LF
    lda #'F'
    jsr OUTCH
    lda #'A'
    jsr OUTCH
    lda #'I'
    jsr OUTCH
    lda #'L'
    jsr OUTCH
    jsr CRLF
    
@done:
    ; -----------------------------------------------------------------------
    ; ALWAYS restore registers before returning
    ; Return with CLC (carry clear) to indicate success to shell
    ; -----------------------------------------------------------------------
    pla
    tay
    pla
    tax
    pla
    plp
    clc              ; Clear carry = success (though shell may ignore)
    rts              ; Return to shell

; ---------------------------------------------------------------------------
; Note: No BSS segment needed for this simple command
; No message strings in RODATA - we use immediate values for clarity
; This keeps the binary small and self-contained
; ---------------------------------------------------------------------------
