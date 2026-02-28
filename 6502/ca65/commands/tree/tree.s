; tree.s - Display directory tree
; Usage: tree [path]

.import pico_send_request, read_byte, send_byte
.import CMD_ID, ARG_LEN, LAST_STATUS, ARG_BUFF

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
CMD_FS_TREE = $27
INPUT_BUFFER = $0300
VIA_DDRA     = $6003

; ---------------------------------------------------------------------------
; Zero Page
; ---------------------------------------------------------------------------
t_str_ptr1   = $5A
t_str_ptr2   = $5C
t_ptr_temp   = $5E
t_count      = $58 ; 2 bytes for length

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

    ; -----------------------------------------------------------------------
    ; Parse Arguments (Optional Path)
    ; -----------------------------------------------------------------------
    lda #<INPUT_BUFFER
    sta t_ptr_temp
    lda #>INPUT_BUFFER
    sta t_ptr_temp+1

    jsr skip_word ; Skip "RUN"
    jsr skip_word ; Skip "/BIN/TREE.BIN"

    ; Copy argument if present
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
    sta ARG_BUFF, x ; Null terminate
    stx ARG_LEN

    ; -----------------------------------------------------------------------
    ; Send Command manually (to handle stream response)
    ; -----------------------------------------------------------------------
    lda #$FF
    sta VIA_DDRA    ; Set Port A to Output

    lda #CMD_FS_TREE
    jsr send_byte
    lda ARG_LEN
    jsr send_byte

    ldx #0
@send_args:
    cpx ARG_LEN
    beq @args_done
    lda ARG_BUFF, x
    jsr send_byte
    inx
    jmp @send_args
@args_done:

    ; -----------------------------------------------------------------------
    ; Read Response Stream
    ; -----------------------------------------------------------------------
    lda #$00
    sta VIA_DDRA    ; Set Port A to Input

    jsr read_byte   ; Status
    cmp #$00        ; STATUS_OK
    bne @error

    jsr read_byte   ; Len Lo
    sta t_count
    jsr read_byte   ; Len Hi
    sta t_count+1

@stream_loop:
    lda t_count
    ora t_count+1
    beq @done

    jsr read_byte
    jsr OUTCH       ; Print char

    ; Decrement counter
    lda t_count
    bne @dec_lo
    dec t_count+1
@dec_lo:
    dec t_count
    jmp @stream_loop

@error:
    ; Consume 2 bytes if error (LenLo, LenHi) to reset bus
    jsr read_byte
    jsr read_byte
    
    lda #<msg_fail
    sta t_str_ptr1
    lda #>msg_fail
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF

@done:
    lda #$FF
    sta VIA_DDRA    ; Restore Port A to Output

    pla
    tay
    pla
    tax
    pla
    plp
    clc
    rts

; ---------------------------------------------------------------------------
; Helper: Skip word
; ---------------------------------------------------------------------------
skip_word:
    ldy #0
@skip_char:
    lda (t_ptr_temp), y
    beq @done
    cmp #' '
    beq @found_space
    inc t_ptr_temp
    bne @skip_char
    inc t_ptr_temp+1
    jmp @skip_char
@found_space:
@skip_spaces:
    lda (t_ptr_temp), y
    beq @done
    cmp #' '
    bne @done
    inc t_ptr_temp
    bne @skip_spaces
    inc t_ptr_temp+1
    jmp @skip_spaces
@done:
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
msg_fail:  .asciiz "Error: Failed to list tree"