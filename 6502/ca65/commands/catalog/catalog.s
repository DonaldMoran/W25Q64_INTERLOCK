; catalog.s - Streaming Directory Listing (CATALOG)
; Usage: CATALOG [path]

.include "../../common/pico_def.inc"

.import read_byte, send_byte
.import ARG_BUFF

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
INPUT_BUFFER = $0300
ACIA_DATA    = $5000

; ---------------------------------------------------------------------------
; Zero Page (Transient Safe Area $58-$5F)
; ---------------------------------------------------------------------------
t_ptr_temp   = $58 ; 2 bytes
t_count      = $5A ; 2 bytes for length
t_line_cnt   = $5C ; 1 byte for paging
t_cwd_ptr    = $5E ; 2 bytes (passed by shell)

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

    ; Skip "RUN" and "/BIN/CATALOG.BIN" (standard transient invocation)
    jsr skip_word
    jsr skip_word

    ; Check if argument exists
    ldy #0
    lda (t_ptr_temp), y
    beq @use_cwd        ; No argument -> use CWD

    ; Check if absolute path (starts with /)
    cmp #'/'
    beq @copy_arg_only

    ; Relative path: Copy CWD first
    ldx #0
    ldy #0
@copy_cwd_rel:
    lda (t_cwd_ptr), y
    beq @check_slash
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_cwd_rel

@check_slash:
    ; Check if we need a separator
    dex
    lda ARG_BUFF, x
    inx
    cmp #'/'
    beq @append_arg
    lda #'/'
    sta ARG_BUFF, x
    inx

@append_arg:
    ldy #0
@copy_arg_loop:
    lda (t_ptr_temp), y
    beq @finish_arg
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_arg_loop

@copy_arg_only:
    ldx #0
    ldy #0
    jmp @copy_arg_loop  ; Reuse loop

@use_cwd:
    ldx #0
    ldy #0
    jmp @copy_cwd_rel   ; Reuse loop (will stop at null, no arg appended)

@finish_arg:
    sta ARG_BUFF, x ; Null terminate
    stx t_ptr_temp  ; Save length temporarily in ZP (low byte)

    ; -----------------------------------------------------------------------
    ; Send Command manually (to handle stream response)
    ; -----------------------------------------------------------------------
    lda #$FF
    sta VIA_DDRA    ; Set Port A to Output

    lda #CMD_FS_LIST
    jsr send_byte
    
    lda t_ptr_temp  ; Get Length
    jsr send_byte

    ldx #0
    lda t_ptr_temp  ; Length
    beq @args_done
@send_args:
    lda ARG_BUFF, x
    jsr send_byte
    inx
    cpx t_ptr_temp
    bne @send_args
@args_done:

    ; -----------------------------------------------------------------------
    ; Read Response Stream
    ; -----------------------------------------------------------------------
    lda #$00
    sta VIA_DDRA    ; Set Port A to Input

    jsr read_byte   ; Status
    cmp #STATUS_OK
    bne @error

    jsr read_byte   ; Len Lo
    sta t_count
    jsr read_byte   ; Len Hi
    sta t_count+1

    jsr CRLF

@stream_loop:
    lda t_count
    ora t_count+1
    beq @done

    jsr read_byte
    jsr paging_outch ; Print char with paging

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
    sta t_ptr_temp
    lda #>msg_fail
    sta t_ptr_temp+1
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
; Helper: Skip word (skips non-spaces, then spaces)
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
    ldy #0
@loop:
    lda (t_ptr_temp), y
    beq @done
    jsr OUTCH
    iny
    jmp @loop
@done:
    rts

; ---------------------------------------------------------------------------
; Helper: Paging Output Char
; ---------------------------------------------------------------------------
paging_outch:
    pha
    jsr OUTCH
    pla
    cmp #$0A
    bne @done
    jsr check_paging
@done:
    rts

check_paging:
    inc t_line_cnt
    lda t_line_cnt
    cmp #22         ; Screen Limit
    bcc @done

    ; Limit reached, pause
    lda #<msg_more
    sta t_ptr_temp
    lda #>msg_more
    sta t_ptr_temp+1
    jsr print_string

@wait_key:
    lda ACIA_DATA
    beq @wait_key   ; Loop until key pressed
    
    jsr CRLF        ; Newline after keypress
    lda #0
    sta t_line_cnt

@done:
    rts

.segment "RODATA"
msg_fail:  .asciiz "Error: Failed to list directory"
msg_more:  .asciiz "--More--"