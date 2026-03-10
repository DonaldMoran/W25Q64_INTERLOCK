; df.s - Disk Free command
; Displays filesystem usage statistics.

.include "pico_def.inc"
.import pico_send_request
.import CMD_ID, ARG_LEN, LAST_STATUS, RESP_LEN, RESP_BUFF

; ---------------------------------------------------------------------------
; System calls
; ---------------------------------------------------------------------------
OUTCH = $FFEF
CRLF  = $FED1

; ---------------------------------------------------------------------------
; Zero Page (USE ONLY $58-$5F)
; ---------------------------------------------------------------------------
t_ptr_temp   = $58  ; 2 bytes - used for passing pointers (Moved to avoid overlap)
t_str_ptr1   = $5A  ; 2 bytes
t_val32      = $5C  ; 4 bytes for 32-bit numbers ($5C-$5F)

; Response buffer offsets (Use = for constants, not .define)
TOTAL_BLOCKS_PTR = RESP_BUFF + 0
USED_BLOCKS_PTR  = RESP_BUFF + 4
BLOCK_SIZE_PTR   = RESP_BUFF + 8

.segment "HEADER"
    .word $0800

.segment "CODE"
start:
    php
    pha
    txa
    pha
    tya
    pha

    ; Sanitize CPU state
    cld
    sei

    ; Send command to Pico
    lda #CMD_FS_SPACE
    sta CMD_ID
    lda #0
    sta ARG_LEN
    jsr pico_send_request

    ; Check status
    lda LAST_STATUS
    bne @error

    ; Print header
    lda #<str_header
    sta t_str_ptr1
    lda #>str_header
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF

    ; --- Calculate and Print Total ---
    lda #<str_total
    sta t_str_ptr1
    lda #>str_total
    sta t_str_ptr1+1
    jsr print_string
    
    ; Pass pointer to helper via ZP
    lda #<TOTAL_BLOCKS_PTR
    sta t_ptr_temp
    lda #>TOTAL_BLOCKS_PTR
    sta t_ptr_temp+1
    jsr print_row_for_ptr

    ; --- Calculate and Print Used ---
    lda #<str_used
    sta t_str_ptr1
    lda #>str_used
    sta t_str_ptr1+1
    jsr print_string

    lda #<USED_BLOCKS_PTR
    sta t_ptr_temp
    lda #>USED_BLOCKS_PTR
    sta t_ptr_temp+1
    jsr print_row_for_ptr

    ; --- Calculate and Print Free ---
    lda #<str_free
    sta t_str_ptr1
    lda #>str_free
    sta t_str_ptr1+1
    jsr print_string

    ; Calculate free blocks (total - used)
    ; 32-bit subtraction: t_val32 = TOTAL - USED
    sec
    lda TOTAL_BLOCKS_PTR+0
    sbc USED_BLOCKS_PTR+0
    sta t_val32+0
    lda TOTAL_BLOCKS_PTR+1
    sbc USED_BLOCKS_PTR+1
    sta t_val32+1
    lda TOTAL_BLOCKS_PTR+2
    sbc USED_BLOCKS_PTR+2
    sta t_val32+2
    lda TOTAL_BLOCKS_PTR+3
    sbc USED_BLOCKS_PTR+3
    sta t_val32+3

    jsr print_row_for_val

    jmp @done

@error:
    lda #<str_error
    sta t_str_ptr1
    lda #>str_error
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF

@done:
    pla
    tay
    pla
    tax
    pla
    plp
    clc
    rts

; ---------------------------------------------------------------------------
; Prints a row of data. Expects pointer to 32-bit value in t_ptr_temp.
; Clobbers: A, X, Y, t_val32
; ---------------------------------------------------------------------------
print_row_for_ptr:
    ; Copy value from (t_ptr_temp) to t_val32
    ldy #0
    lda (t_ptr_temp),y
    sta t_val32+0
    iny
    lda (t_ptr_temp),y
    sta t_val32+1
    iny
    lda (t_ptr_temp),y
    sta t_val32+2
    iny
    lda (t_ptr_temp),y
    sta t_val32+3
    ; Fall through to print_row_for_val

; ---------------------------------------------------------------------------
; Prints a row of data. Expects 32-bit value in t_val32.
; Clobbers: A, X, Y
; ---------------------------------------------------------------------------
print_row_for_val:
    ; Save t_val32 because print_32bit_decimal destroys it
    lda t_val32+3
    pha
    lda t_val32+2
    pha
    lda t_val32+1
    pha
    lda t_val32+0
    pha

    jsr print_32bit_decimal

    lda #<str_blocks
    sta t_str_ptr1
    lda #>str_blocks
    sta t_str_ptr1+1
    jsr print_string

    ; Restore t_val32
    pla
    sta t_val32+0
    pla
    sta t_val32+1
    pla
    sta t_val32+2
    pla
    sta t_val32+3

    ; Save t_val32 again for MB calculation
    lda t_val32+3
    pha
    lda t_val32+2
    pha
    lda t_val32+1
    pha
    lda t_val32+0
    pha

    ; Calculate KB = blocks * 4 (since block size is 4096)
    ; This is a 32-bit left shift by 2
    asl t_val32+0
    rol t_val32+1
    rol t_val32+2
    rol t_val32+3
    asl t_val32+0
    rol t_val32+1
    rol t_val32+2
    rol t_val32+3

    jsr print_32bit_decimal
    
    lda #<str_kb
    sta t_str_ptr1
    lda #>str_kb
    sta t_str_ptr1+1
    jsr print_string

    ; Restore t_val32 (Blocks)
    pla
    sta t_val32+0
    pla
    sta t_val32+1
    pla
    sta t_val32+2
    pla
    sta t_val32+3

    ; Calculate MB = Blocks / 256 (Right shift by 8)
    lda t_val32+1
    sta t_val32+0
    lda t_val32+2
    sta t_val32+1
    lda t_val32+3
    sta t_val32+2
    lda #0
    sta t_val32+3

    jsr print_32bit_decimal

    lda #<str_mb
    sta t_str_ptr1
    lda #>str_mb
    sta t_str_ptr1+1
    jsr print_string
    
    jsr CRLF
    rts

; ---------------------------------------------------------------------------
; Helper: Print null-terminated string from t_str_ptr1
; ---------------------------------------------------------------------------
print_string:
    pha
    phy
    ldy #0
@loop:
    lda (t_str_ptr1), y
    beq @done
    jsr OUTCH
    iny
    jmp @loop
@done:
    ply
    pla
    rts

; ---------------------------------------------------------------------------
; Helper: Print 32-bit unsigned decimal from t_val32
; Clobbers A, X, Y
; ---------------------------------------------------------------------------
print_32bit_decimal:
    ldx #10 ; Max 10 digits for 32-bit
@outer_loop:
    ldy #32 ; 32 bits to divide
    lda #0  ; Remainder
@inner_loop:
    asl t_val32+0
    rol t_val32+1
    rol t_val32+2
    rol t_val32+3
    rol a
    cmp #10
    bcc @no_sub
    sbc #10
    inc t_val32+0 ; Set quotient bit
@no_sub:
    dey
    bne @inner_loop
    
    pha ; Save digit
    dex
    bne @outer_loop

    ; Print digits
    ldx #10
    ldy #0 ; Flag to skip leading zeros
@print_loop:
    pla
    ora #$30
    cmp #'0'
    bne @not_zero
    cpx #1 ; Is it the last digit?
    beq @force_print
    cpy #0 ; Is it a leading zero?
    beq @skip_print ; Yes, skip
@force_print:
@not_zero:
    ldy #1 ; Found a non-zero digit
    jsr OUTCH
@skip_print:
    dex
    bne @print_loop
    rts

.segment "RODATA"
str_header: .asciiz "Filesystem Usage"
str_total:  .asciiz "Total: "
str_used:   .asciiz " Used: "
str_free:   .asciiz " Free: "
str_blocks: .asciiz " Blocks ("
str_kb:     .asciiz " KB, "
str_mb:     .asciiz " MB)"
str_error:  .asciiz "Error: Filesystem not mounted or corrupt."