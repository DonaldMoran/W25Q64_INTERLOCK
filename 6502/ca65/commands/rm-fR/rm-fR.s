; rm-fr.s - Recursive Remove Command
; Usage: rm-fr <path>

.include "pico_def.inc"
.import pico_send_request
.import CMD_ID, ARG_LEN, LAST_STATUS, ARG_BUFF

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
INPUT_BUFFER = $0300

; ---------------------------------------------------------------------------
; Zero Page (USE ONLY $58-$5F)
; ---------------------------------------------------------------------------
t_str_ptr1   = $5A
t_str_ptr2   = $5C
t_ptr_temp   = $5E

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

    ; -----------------------------------------------------------------------
    ; Parse Arguments
    ; The shell executes us via: RUN /BIN/RM-FR.BIN <ARGS>
    ; So INPUT_BUFFER contains: "RUN /BIN/RM-FR.BIN <ARGS>"
    ; We need to skip the first two words ("RUN" and the binary path)
    ; -----------------------------------------------------------------------
    
    ; Point to INPUT_BUFFER
    lda #<INPUT_BUFFER
    sta t_ptr_temp
    lda #>INPUT_BUFFER
    sta t_ptr_temp+1

    ; Skip "RUN"
    jsr skip_word
    ; Skip "/BIN/RM-FR.BIN"
    jsr skip_word

    ; Check if we have an argument left
    ldy #0
    lda (t_ptr_temp), y
    bne @has_arg
    
    ; No argument provided
    lda #<msg_usage
    sta t_str_ptr1
    lda #>msg_usage
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    jmp done

@has_arg:
    ; Copy argument to ARG_BUFF
    ldx #0
@copy_loop:
    lda (t_ptr_temp), y
    beq @copy_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_loop
@copy_done:
    lda #0              ; Null terminate
    sta ARG_BUFF, x
    inx                 ; Include null terminator in length
    stx ARG_LEN

    ; -----------------------------------------------------------------------
    ; Send Command
    ; -----------------------------------------------------------------------
    lda #CMD_FS_REMOVE_RECURSIVE
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
; Helper: Skip one word and subsequent spaces in (t_ptr_temp)
; ---------------------------------------------------------------------------
skip_word:
    ldy #0
@skip_chars:
    lda (t_ptr_temp), y
    beq @sw_done
    cmp #' '
    beq @found_space
    iny
    jmp @skip_chars
@found_space:
@skip_spaces:
    iny
    lda (t_ptr_temp), y
    beq @sw_done
    cmp #' '
    beq @skip_spaces
@sw_done:
    tya
    clc
    adc t_ptr_temp
    sta t_ptr_temp
    lda #0
    adc t_ptr_temp+1
    sta t_ptr_temp+1
    rts

; ---------------------------------------------------------------------------
; Helper: Print String
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

.segment "RODATA"
msg_usage: .asciiz "Usage: rm-fr <path>"
msg_fail:  .asciiz "Error: Failed to remove"