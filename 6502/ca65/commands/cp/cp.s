; cp.s - Copy File
; Usage: CP <src> <dst>

.import pico_send_request
.import CMD_ID, ARG_LEN, LAST_STATUS, ARG_BUFF

CMD_FS_COPY = $19
INPUT_BUFFER = $0300

t_str_ptr1   = $5A
t_ptr_temp   = $5E ; CWD Pointer from Shell
t_arg_ptr    = $58 ; Temp pointer for parsing

OUTCH = $FFEF
CRLF  = $FED1

.segment "HEADER"
    .word $0800

.segment "CODE"
start:
    ; Setup input pointer
    lda #<INPUT_BUFFER
    sta t_arg_ptr
    lda #>INPUT_BUFFER
    sta t_arg_ptr+1

    ; Skip "RUN" and Binary Name
    jsr skip_word
    jsr skip_word

    ; --- Parse Source ---
    ldx #0          ; ARG_BUFF index
    jsr parse_path
    cpx #0
    beq show_usage  ; No source provided

    ; Null terminate Source
    lda #0
    sta ARG_BUFF, x
    inx

    ; --- Parse Dest ---
    jsr parse_path
    
    ; Null terminate Dest
    lda #0
    sta ARG_BUFF, x
    inx
    stx ARG_LEN

    ; --- Send Command ---
    lda #CMD_FS_COPY
    sta CMD_ID
    jsr pico_send_request

    lda LAST_STATUS
    cmp #$00
    beq done

    ; Error
    lda #<msg_err
    sta t_str_ptr1
    lda #>msg_err
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF

done:
    ; Standard Exit: Restore registers and return
    pla
    tay
    pla
    tax
    pla
    plp
    clc
    rts

show_usage:
    lda #<msg_usage
    sta t_str_ptr1
    lda #>msg_usage
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    jmp done

; ---------------------------------------------------------------------------
; parse_path
; Reads word from (t_arg_ptr), resolves relative path, writes to ARG_BUFF[X]
; Updates X and t_arg_ptr.
; ---------------------------------------------------------------------------
parse_path:
    ; 1. Skip leading spaces
    ldy #0
@skip_space:
    lda (t_arg_ptr), y
    beq @done           ; End of line
    cmp #' '
    bne @found_start
    inc t_arg_ptr
    bne @skip_space
    inc t_arg_ptr+1
    jmp @skip_space

@found_start:
    ; 2. Check if absolute (starts with /)
    cmp #'/'
    beq @copy_word      ; Absolute, just copy

    ; 3. Relative: Copy CWD first
    ; Save Y (index into input)
    tya
    pha
    
    ldy #0
@copy_cwd:
    lda (t_ptr_temp), y ; Read from CWD
    beq @cwd_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_cwd
@cwd_done:
    ; Ensure trailing slash
    dex
    lda ARG_BUFF, x
    inx
    cmp #'/'
    beq @has_slash
    lda #'/'
    sta ARG_BUFF, x
    inx
@has_slash:
    pla
    tay ; Restore input index (should be 0)

@copy_word:
    lda (t_arg_ptr), y
    beq @done
    cmp #' '
    beq @done
    sta ARG_BUFF, x
    inx
    inc t_arg_ptr
    bne @copy_word
    inc t_arg_ptr+1
    jmp @copy_word
@done:
    rts

; ---------------------------------------------------------------------------
; skip_word: Advances t_arg_ptr past current word and spaces
; ---------------------------------------------------------------------------
skip_word:
    ldy #0
@find_space:
    lda (t_arg_ptr), y
    beq @rts
    cmp #' '
    beq @skip_spaces
    inc t_arg_ptr
    bne @find_space
    inc t_arg_ptr+1
    jmp @find_space
@skip_spaces:
    lda (t_arg_ptr), y
    cmp #' '
    bne @rts
    inc t_arg_ptr
    bne @skip_spaces
    inc t_arg_ptr+1
    jmp @skip_spaces
@rts: rts

print_string:
    ldy #0
@loop:
    lda (t_str_ptr1), y
    beq @rts
    jsr OUTCH
    iny
    jmp @loop
@rts: rts

.segment "RODATA"
msg_usage: .asciiz "Usage: CP <src> <dst>"
msg_err:   .asciiz "Error: Copy failed"