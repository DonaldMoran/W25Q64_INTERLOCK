; tree.s - Display directory tree
; Usage: tree [path]

.include "pico_def.inc"
.import pico_send_request, read_byte, send_byte
.import CMD_ID, ARG_LEN, LAST_STATUS, ARG_BUFF

INPUT_BUFFER = $0300
ACIA_DATA    = $5000

; ---------------------------------------------------------------------------
; Zero Page
; ---------------------------------------------------------------------------
t_str_ptr1   = $5A
t_line_cnt  = $5C ; Replaces unused t_str_ptr2
t_ptr_temp   = $5E
t_len_cnt    = $58 ; 2 bytes for length

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

    ; Initialize paging counter
    lda #0
    sta t_line_cnt

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

    ; Wait for initial response from Pico (Status + 2 bytes Len)
    jsr read_byte   ; Status
    pha             ; Save status
    jsr read_byte   ; consume len_lo
    jsr read_byte   ; consume len_hi
    pla             ; Restore status
    cmp #$00        ; STATUS_OK
    bne @error

@read_frame_len:
    jsr read_byte
    sta t_len_cnt
    jsr read_byte
    sta t_len_cnt+1

    lda t_len_cnt
    ora t_len_cnt+1
    beq @done

@read_frame_data:
    jsr read_byte
    jsr paging_outch ; Print char with pagination

    sec
    lda t_len_cnt
    sbc #1
    sta t_len_cnt
    lda t_len_cnt+1
    sbc #0
    sta t_len_cnt+1

    lda t_len_cnt
    ora t_len_cnt+1
    bne @read_frame_data

    jmp @read_frame_len

@error:
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
msg_more:  .asciiz "--More--"

; ---------------------------------------------------------------------------
; Helper: Paging output routines (adapted from rlist)
; ---------------------------------------------------------------------------
paging_outch:
    pha
    jsr OUTCH
    pla
    cmp #$0A        ; is it a newline?
    bne @done
    jsr check_paging
@done:
    rts

check_paging:
    inc t_line_cnt
    lda t_line_cnt
    cmp #22         ; 22 lines per page
    bcc @done

    ; Print --More-- and wait for key
    lda #<msg_more
    sta t_str_ptr1
    lda #>msg_more
    sta t_str_ptr1+1
    jsr print_string

@wait_key:
    lda ACIA_DATA
    beq @wait_key
    jsr CRLF
    lda #0
    sta t_line_cnt
.segment "RODATA"
@done:
    rts