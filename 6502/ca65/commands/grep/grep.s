; grep.s - Search for a pattern in a file
; Usage: GREP <pattern> <filename>

.include "../../common/pico_def.inc"

.import read_byte, send_byte
.import ARG_BUFF

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
INPUT_BUFFER = $0300
READ_CHUNK_SIZE = 128
LINE_BUF_SIZE = 128
PATTERN_BUF_SIZE = 64

; ---------------------------------------------------------------------------
; Zero Page (Transient Safe Area $58-$5F)
; ---------------------------------------------------------------------------
t_ptr_temp   = $58 ; 2 bytes
t_bytes_read = $5B ; 1 byte (used as temp)
t_cwd_ptr    = $5E ; 2 bytes (passed by shell)

; For strstr
s_haystack = $58 ; Overlaps t_ptr_temp
s_needle   = $5A ; Overlaps t_handle (safe now that handle is in BSS)
s_h_ptr    = $5C ; Temp pointer for haystack
s_n_ptr    = $5E ; Temp pointer for needle

; ---------------------------------------------------------------------------
; System calls
; ---------------------------------------------------------------------------
OUTCH  = $FFEF
CRLF   = $FED1

.segment "HEADER"
    .word $0800

.segment "BSS"
read_buf:       .res READ_CHUNK_SIZE
line_buf:       .res LINE_BUF_SIZE
pattern_buf:    .res PATTERN_BUF_SIZE
line_idx:       .res 1
read_idx:       .res 1
read_len:       .res 1
file_handle:    .res 1

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

    ; Initialize variables
    lda #0
    sta line_idx

    ; -----------------------------------------------------------------------
    ; Parse Arguments
    ; -----------------------------------------------------------------------
    lda #<INPUT_BUFFER
    sta t_ptr_temp
    lda #>INPUT_BUFFER
    sta t_ptr_temp+1

    ; Skip "RUN" and "/BIN/GREP.BIN"
    jsr skip_word
    jsr skip_word

    ; 1. Get Pattern
    ldy #0
    ldx #0
@copy_pattern:
    lda (t_ptr_temp), y
    bne @check_space_1
    jmp usage_error ; Not enough args
@check_space_1:
    cmp #' '
    beq @pattern_done
    sta pattern_buf, x
    inx
    iny
    cpx #PATTERN_BUF_SIZE-1
    bcc @copy_pattern
@pattern_done:
    lda #0
    sta pattern_buf, x

    ; Skip spaces to find filename
@skip_spaces:
    lda (t_ptr_temp), y
    bne @check_space_2
    jmp usage_error
@check_space_2:
    cmp #' '
    bne @filename_found
    iny
    jmp @skip_spaces

@filename_found:
    ; Update t_ptr_temp to point to filename
    tya
    clc
    adc t_ptr_temp
    sta t_ptr_temp
    lda #0
    adc t_ptr_temp+1
    sta t_ptr_temp+1

    ; 2. Resolve Filename
    ldy #0
    lda (t_ptr_temp), y
    cmp #'/'
    beq @copy_arg_only

    ; Relative path
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
    jmp @copy_arg_loop

@finish_arg:
    lda #0
    sta ARG_BUFF, x
    inx
    lda #1          ; Mode 1 = Read Only
    sta ARG_BUFF, x
    inx
    stx t_bytes_read ; Save length temporarily

    ; -----------------------------------------------------------------------
    ; Open File
    ; -----------------------------------------------------------------------
    lda #$FF
    sta VIA_DDRA
    lda #CMD_FS_OPEN
    jsr send_byte
    lda t_bytes_read
    jsr send_byte
    ldx #0
@send_open_args:
    cpx t_bytes_read
    beq @open_args_done
    lda ARG_BUFF, x
    jsr send_byte
    inx
    jmp @send_open_args
@open_args_done:
    lda #$00
    sta VIA_DDRA
    jsr read_byte
    cmp #STATUS_OK
    beq @open_ok
    jsr read_byte ; consume len lo
    jsr read_byte ; consume len hi
    jmp file_error

@open_ok:
    jsr read_byte ; len lo
    jsr read_byte ; len hi
    jsr read_byte ; handle
    sta file_handle
    jsr read_byte ; size
    jsr read_byte
    jsr read_byte
    jsr read_byte

    ; -----------------------------------------------------------------------
    ; Main Read Loop
    ; -----------------------------------------------------------------------
@read_chunk_loop:
    lda #$FF
    sta VIA_DDRA
    lda #CMD_FS_READ
    jsr send_byte
    lda #3
    jsr send_byte
    lda file_handle
    jsr send_byte
    lda #<READ_CHUNK_SIZE
    jsr send_byte
    lda #>READ_CHUNK_SIZE
    jsr send_byte
    lda #$00
    sta VIA_DDRA
    jsr read_byte
    cmp #STATUS_OK
    beq @read_len_check
    jsr read_byte ; consume len lo
    jsr read_byte ; consume len hi
    jmp @close_file
@read_len_check:
    jsr read_byte
    sta read_len
    jsr read_byte ; len hi
    lda read_len
    beq @process_final_line ; EOF

    ; Read chunk into buffer
    ldx #0
@read_data_loop:
    cpx read_len
    beq @process_chunk
    jsr read_byte
    sta read_buf, x
    inx
    jmp @read_data_loop

@process_chunk:
    lda #0
    sta read_idx
@process_loop:
    ldx read_idx
    cpx read_len
    beq @read_chunk_loop ; Finished chunk, get next

    lda read_buf, x
    inc read_idx
    
    cmp #$0A ; Newline
    bne @store_char

    ; Process line
    jsr process_line
    jmp @process_loop

@store_char:
    ldy line_idx
    cpy #LINE_BUF_SIZE - 1
    bcc @do_store
    ; Line buffer full, treat as a line and reset
    jsr process_line
    jmp @process_loop
@do_store:
    sta line_buf, y
    inc line_idx
    jmp @process_loop

@process_final_line:
    ; If there's anything left in the line buffer at EOF, process it
    lda line_idx
    beq @close_file
    jsr process_line

@close_file:
    lda #$FF
    sta VIA_DDRA
    lda #CMD_FS_CLOSE
    jsr send_byte
    lda #1
    jsr send_byte
    lda file_handle
    jsr send_byte
    lda #$00
    sta VIA_DDRA
    jsr read_byte
    jsr read_byte
    jsr read_byte

done:
    pla
    tay
    pla
    tax
    pla
    plp
    clc
    rts

usage_error:
    lda #<msg_usage
    sta t_ptr_temp
    lda #>msg_usage
    sta t_ptr_temp+1
    jsr print_string
    jsr CRLF
    jmp done

file_error:
    lda #<msg_fail
    sta t_ptr_temp
    lda #>msg_fail
    sta t_ptr_temp+1
    jsr print_string
    jsr CRLF
    jmp done

; ---------------------------------------------------------------------------
; Helpers
; ---------------------------------------------------------------------------

process_line:
    ldy line_idx
    lda #0
    sta line_buf, y
    lda #<line_buf
    sta s_haystack
    lda #>line_buf
    sta s_haystack+1
    lda #<pattern_buf
    sta s_needle
    lda #>pattern_buf
    sta s_needle+1
    jsr strstr
    bcs @line_done
    
    lda #<line_buf
    sta t_ptr_temp
    lda #>line_buf
    sta t_ptr_temp+1
    jsr print_string
    jsr CRLF

@line_done:
    lda #0
    sta line_idx
    rts

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
    bne @sw_done
    jmp @skip_spaces
@sw_done:
    tya
    clc
    adc t_ptr_temp
    sta t_ptr_temp
    lda #0
    adc t_ptr_temp+1
    sta t_ptr_temp+1
    rts

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

; --- strstr: Find needle in haystack ---
; In: s_haystack (ptr), s_needle (ptr)
; Out: Carry clear on match, set on no match
strstr:
    phy
    lda s_haystack
    sta s_h_ptr
    lda s_haystack+1
    sta s_h_ptr+1

@outer_loop:
    lda s_h_ptr
    pha
    lda s_h_ptr+1
    pha
    lda s_needle
    sta s_n_ptr
    lda s_needle+1
    sta s_n_ptr+1
    ldy #0
@inner_loop:
    lda (s_n_ptr), y
    beq @found_match
    lda (s_h_ptr), y
    beq @no_match_inner
    cmp (s_n_ptr), y
    bne @no_match_inner
    iny
    jmp @inner_loop

@no_match_inner:
    pla
    sta s_h_ptr+1
    pla
    sta s_h_ptr
    inc s_h_ptr
    bne @check_end
    inc s_h_ptr+1
@check_end:
    ldy #0
    lda (s_h_ptr), y
    beq @not_found
    jmp @outer_loop

@found_match:
    pla
    pla
    ply
    clc
    rts

@not_found:
    ply
    sec
    rts

.segment "RODATA"
msg_usage: .asciiz "Usage: GREP <pattern> <filename>"
msg_fail:  .asciiz "Error: File not found"