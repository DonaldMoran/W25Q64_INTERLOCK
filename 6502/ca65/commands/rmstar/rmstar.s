; rmstar.s - Delete all files in current directory
; Usage: rm*

.include "pico_def.inc"
.import pico_send_request
.import CMD_ID, ARG_LEN, LAST_STATUS, ARG_BUFF

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; Zero Page (USE ONLY $58-$5F)
; ---------------------------------------------------------------------------
t_str_ptr1   = $5A
t_str_ptr2   = $5C
t_ptr_temp   = $5E ; This is where Shell passes CWD pointer

; ---------------------------------------------------------------------------
; System calls
; ---------------------------------------------------------------------------
OUTCH = $FFEF
CRLF  = $FED1

.segment "HEADER"
    .word $0800

.segment "CODE"
start:
    ; Save registers
    php
    pha
    txa
    pha
    tya
    pha

    ; Sanitize CPU state
    cld
    sei

    ; Print "Deleting all files in "
    lda #<msg_start
    sta t_str_ptr1
    lda #>msg_start
    sta t_str_ptr1+1
    jsr print_string

    ; Print CWD (pointed to by t_ptr_temp/$5E)
    lda t_ptr_temp
    sta t_str_ptr1
    lda t_ptr_temp+1
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF

    ; -----------------------------------------------------------------------
    ; Copy CWD to ARG_BUFF
    ; -----------------------------------------------------------------------
    ldy #0
    ldx #0
@copy_loop:
    lda (t_ptr_temp), y
    beq @copy_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_loop
@copy_done:
    lda #0
    sta ARG_BUFF, x
    inx
    stx ARG_LEN

    ; -----------------------------------------------------------------------
    ; Send Command
    ; -----------------------------------------------------------------------
    lda #CMD_FS_DELETE_CONTENTS
    sta CMD_ID
    
    jsr pico_send_request
    
    ; Check Status
    lda LAST_STATUS
    cmp #$00 ; STATUS_OK
    beq done
    
    ; Error
    lda #<msg_fail
    sta t_str_ptr1
    lda #>msg_fail
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF

done:
    pla
    tay
    pla
    tax
    pla
    plp
    clc
    rts

; ---------------------------------------------------------------------------
; Helper: Print String
; ---------------------------------------------------------------------------
print_string:
    pha
    tya
    pha
    ldy #0
@loop:
    lda (t_str_ptr1), y
    beq @done
    jsr OUTCH
    iny
    jmp @loop
@done:
    pla
    tay
    pla
    rts

.segment "RODATA"
msg_start: .asciiz "Deleting all files in "
msg_fail:  .asciiz "Error: Failed to delete contents"