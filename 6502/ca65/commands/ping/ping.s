; ping.s - Definitive 65C02 transient command example
; Location: 6502/ca65/commands/ping/ping.s
;
; This command demonstrates the proper pattern for all transient commands:
; 1. Proper zero page usage ($58-$5F only)
; 2. 65C02 instructions (PHY/PLY) - works with your emulator
; 3. Communication with Pico via pico_send_request
; 4. Direct screen output using .asciiz strings
; 5. Register preservation
; 6. Comprehensive debug output
; 7. Clear success/failure indicators

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
t_str_ptr1   = $5A  ; 2 bytes - String pointer 1
t_str_ptr2   = $5C  ; 2 bytes - String pointer 2
t_ptr_temp   = $5E  ; 2 bytes - Temporary pointer

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
    
    ; Sanitize CPU state
    cld
    sei
    
    ; ==================== Show we're running ====================
    lda #<debug_prefix
    sta t_str_ptr1
    lda #>debug_prefix
    sta t_str_ptr1+1
    jsr print_string
    ; =============================================================
    
    ; -----------------------------------------------------------------------
    ; Send PING command to Pico
    ; Command format: CMD_ID = $01 (CMD_SYS_PING), ARG_LEN = 0
    ; -----------------------------------------------------------------------
    lda #$01
    sta CMD_ID
    lda #$00
    sta ARG_LEN
    
    ; ==================== Show command being sent ====================
    lda #<debug_cmd
    sta t_str_ptr1
    lda #>debug_cmd
    sta t_str_ptr1+1
    jsr print_string
    
    lda CMD_ID
    jsr print_hex
    ; ================================================================
    
    jsr pico_send_request   ; Send command and wait for response
    
    ; ==================== Show we returned ====================
    lda #' '
    jsr OUTCH
    lda #<debug_status
    sta t_str_ptr1
    lda #>debug_status
    sta t_str_ptr1+1
    jsr print_string
    
    lda LAST_STATUS
    jsr print_hex
    jsr CRLF
    ; ===========================================================
    
    ; -----------------------------------------------------------------------
    ; Check result and print appropriate message
    ; LAST_STATUS contains result from Pico ($00 = OK, non-zero = error)
    ; -----------------------------------------------------------------------
    lda LAST_STATUS
    bne fail
    
    ; Success - print "PONG"
    lda #<msg_pong
    sta t_str_ptr1
    lda #>msg_pong
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    jmp done
    
fail:
    ; Failure - print "FAIL"
    lda #<msg_fail
    sta t_str_ptr1
    lda #>msg_fail
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    
done:
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
; Helper: Print null-terminated string at (t_str_ptr1)
; Uses 65C02 PHY/PLY instructions
; ---------------------------------------------------------------------------
print_string:
    pha              ; Save A
    phy              ; Save Y (65C02 instruction)
    ldy #0
@loop:
    lda (t_str_ptr1), y
    beq @done
    jsr OUTCH
    iny
    jmp @loop
@done:
    ply              ; Restore Y (65C02 instruction)
    pla              ; Restore A
    rts

; ---------------------------------------------------------------------------
; Helper: Print byte in A as two hex digits
; ---------------------------------------------------------------------------
print_hex:
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr print_nibble
    pla
    and #$0F
    jsr print_nibble
    rts

print_nibble:
    cmp #10
    bcc digit
    adc #6          ; Carry is set from compare
digit:
    adc #'0'
    jsr OUTCH
    rts

; ---------------------------------------------------------------------------
; RODATA - Read-only strings at END of file
; This ensures CODE starts at $0800 as required by HEADER
; ---------------------------------------------------------------------------
.segment "RODATA"

debug_prefix:    .asciiz "PING: "
debug_cmd:       .asciiz "Cmd="
debug_status:    .asciiz "Status="
msg_pong:        .asciiz "PONG"
msg_fail:        .asciiz "FAIL"

; ---------------------------------------------------------------------------
; Note: This is the definitive pattern for all transient commands:
; - Use $58-$5F for zero page (never $50-$57)
; - Preserve all registers on entry, restore on exit
; - Use 65C02 instructions (PHY/PLY) if available
; - Store all strings in RODATA at the end
; - Return with CLC
; - Include debug output that shows what's happening
; ---------------------------------------------------------------------------
