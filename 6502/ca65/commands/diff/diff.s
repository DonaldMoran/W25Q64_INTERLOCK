; diff.s - Compare two files
; Usage: DIFF <file1> <file2>

.include "../../common/pico_def.inc"

.import read_byte, send_byte
.import ARG_BUFF

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
INPUT_BUFFER = $0300
ACIA_DATA    = $5000
READ_CHUNK_SIZE = 128

; ---------------------------------------------------------------------------
; Zero Page (Transient Safe Area $58-$5F)
; ---------------------------------------------------------------------------
t_ptr_temp   = $58 ; 2 bytes
t_handle1    = $5A ; 1 byte
t_handle2    = $5B ; 1 byte
t_len1       = $5C ; 1 byte
t_len2       = $5D ; 1 byte
t_cwd_ptr    = $5E ; 2 bytes (passed by shell, reused as temp len)
t_temp_len   = $5E ; 1 byte (reused)

; ---------------------------------------------------------------------------
; System calls
; ---------------------------------------------------------------------------
OUTCH  = $FFEF
CRLF   = $FED1
OUTHEX = $FFDC

.segment "HEADER"
    .word $0800

.segment "BSS"
read_buf1:  .res READ_CHUNK_SIZE
read_buf2:  .res READ_CHUNK_SIZE
offset:     .res 4 ; 32-bit offset counter

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

    ; Initialize offset
    lda #0
    sta offset
    sta offset+1
    sta offset+2
    sta offset+3

    ; -----------------------------------------------------------------------
    ; Parse Arguments
    ; -----------------------------------------------------------------------
    lda #<INPUT_BUFFER
    sta t_ptr_temp
    lda #>INPUT_BUFFER
    sta t_ptr_temp+1

    ; Skip "RUN" and "/BIN/DIFF.BIN"
    jsr skip_word
    jsr skip_word

    ; -----------------------------------------------------------------------
    ; Open File 1
    ; -----------------------------------------------------------------------
    ; Check for argument 1
    ldy #0
    lda (t_ptr_temp), y
    bne @arg1_found
    jmp usage_error
@arg1_found:

    ; Resolve path for File 1
    jsr resolve_path
    
    ; Open File 1
    jsr open_file
    bcc @file1_ok
    jmp @file1_fail
@file1_ok:
    sta t_handle1

    ; Advance t_ptr_temp to next argument
    jsr skip_word

    ; -----------------------------------------------------------------------
    ; Open File 2
    ; -----------------------------------------------------------------------
    ; Check for argument 2
    ldy #0
    lda (t_ptr_temp), y
    bne @arg2_found
    ; Close file 1 and error
    lda t_handle1
    jsr close_file
    jmp usage_error
@arg2_found:

    ; Resolve path for File 2
    jsr resolve_path
    
    ; Open File 2
    jsr open_file
    bcc @file2_ok
    jmp @file2_fail
@file2_ok:
    sta t_handle2

    ; -----------------------------------------------------------------------
    ; Compare Loop
    ; -----------------------------------------------------------------------
@compare_loop:
    ; Read Chunk 1
    lda t_handle1
    ldx #<read_buf1
    ldy #>read_buf1
    jsr read_chunk
    sta t_len1
    
    ; Read Chunk 2
    lda t_handle2
    ldx #<read_buf2
    ldy #>read_buf2
    jsr read_chunk
    sta t_len2

    ; Compare lengths
    lda t_len1
    cmp t_len2
    beq @lengths_equal
    jmp @size_mismatch_check

    ; Lengths equal. If 0, we are done (Identical).
@lengths_equal:
    lda t_len1
    bne @not_identical
    jmp @identical
@not_identical:

    ; Compare buffers
    ldx #0
@buf_cmp_loop:
    cpx t_len1
    beq @chunk_done
    
    lda read_buf1, x
    cmp read_buf2, x
    beq @match_byte
    jmp @content_mismatch
@match_byte:
    
    inx
    jmp @buf_cmp_loop

@chunk_done:
    ; Add length to offset
    clc
    lda offset
    adc t_len1
    sta offset
    lda offset+1
    adc #0
    sta offset+1
    lda offset+2
    adc #0
    sta offset+2
    lda offset+3
    adc #0
    sta offset+3
    
    jmp @compare_loop

@size_mismatch_check:
    ; If lengths differ, we have a mismatch.
    ; We should compare up to min(len1, len2) to see if there is a content diff first.
    
    ; Find min length
    lda t_len1
    cmp t_len2
    bcc @use_len1
    lda t_len2
@use_len1:
    sta t_temp_len ; use as temp len
    
    ; Compare up to min length
    ldx #0
@buf_cmp_loop_mismatch:
    cpx t_temp_len
    beq @eof_mismatch ; Reached end of shorter chunk without diff -> Size mismatch
    
    lda read_buf1, x
    cmp read_buf2, x
    bne @content_mismatch
    
    inx
    jmp @buf_cmp_loop_mismatch

@eof_mismatch:
    ; Files differ in size (one ended before the other)
    lda #<msg_diff_size
    sta t_ptr_temp
    lda #>msg_diff_size
    sta t_ptr_temp+1
    jsr print_string
    jsr CRLF
    jmp cleanup

@content_mismatch:
    ; Mismatch at index X in current chunk
    ; Total offset = offset + X
    ; Print "Diff at offset X: AA vs BB"
    
    ; Add X to offset for display
    txa
    clc
    adc offset
    sta offset
    lda offset+1
    adc #0
    sta offset+1
    lda offset+2
    adc #0
    sta offset+2
    lda offset+3
    adc #0
    sta offset+3
    
    lda #<msg_diff_at
    sta t_ptr_temp
    lda #>msg_diff_at
    sta t_ptr_temp+1
    jsr print_string
    
    ; Print Offset (32-bit hex)
    lda offset+3
    jsr OUTHEX
    lda offset+2
    jsr OUTHEX
    lda offset+1
    jsr OUTHEX
    lda offset
    jsr OUTHEX
    
    lda #':'
    jsr OUTCH
    lda #' '
    jsr OUTCH
    
    ; Print byte 1
    lda read_buf1, x
    jsr OUTHEX
    
    lda #<msg_vs
    sta t_ptr_temp
    lda #>msg_vs
    sta t_ptr_temp+1
    jsr print_string
    
    ; Print byte 2
    lda read_buf2, x
    jsr OUTHEX
    
    jsr CRLF
    jmp cleanup

@identical:
    lda #<msg_identical
    sta t_ptr_temp
    lda #>msg_identical
    sta t_ptr_temp+1
    jsr print_string
    jsr CRLF
    jmp cleanup

@file1_fail:
    lda #<msg_fail_open
    sta t_ptr_temp
    lda #>msg_fail_open
    sta t_ptr_temp+1
    jsr print_string
    jsr CRLF
    jmp done

@file2_fail:
    lda t_handle1
    jsr close_file
    lda #<msg_fail_open
    sta t_ptr_temp
    lda #>msg_fail_open
    sta t_ptr_temp+1
    jsr print_string
    jsr CRLF
    jmp done

cleanup:
    lda t_handle1
    jsr close_file
    lda t_handle2
    jsr close_file

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

; ---------------------------------------------------------------------------
; Helpers
; ---------------------------------------------------------------------------

; Resolve path from t_ptr_temp to ARG_BUFF
resolve_path:
    ldy #0
    lda (t_ptr_temp), y
    cmp #'/'
    beq @abs_path

    ; Relative path
    ldx #0
    ldy #0
@copy_cwd:
    lda (t_cwd_ptr), y
    beq @check_slash
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_cwd
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
@copy_arg:
    lda (t_ptr_temp), y
    beq @finish
    cmp #' '
    beq @finish
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_arg

@abs_path:
    ldx #0
    ldy #0
@copy_abs:
    lda (t_ptr_temp), y
    beq @finish
    cmp #' '
    beq @finish
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_abs

@finish:
    lda #0
    sta ARG_BUFF, x
    inx
    lda #1 ; Read Only
    sta ARG_BUFF, x
    inx
    stx t_len1 ; Temp save length
    rts

; Open file in ARG_BUFF. Returns Handle in A. Carry set on error.
open_file:
    lda #$FF
    sta VIA_DDRA
    lda #CMD_FS_OPEN
    jsr send_byte
    lda t_len1 ; Length saved in resolve_path
    jsr send_byte
    
    ldx #0
@send_args:
    cpx t_len1
    beq @args_done
    lda ARG_BUFF, x
    jsr send_byte
    inx
    jmp @send_args
@args_done:

    lda #$00
    sta VIA_DDRA
    jsr read_byte ; Status
    cmp #STATUS_OK
    beq @ok
    
    ; Error
    jsr read_byte ; len lo
    jsr read_byte ; len hi
    sec
    rts
@ok:
    jsr read_byte ; len lo
    jsr read_byte ; len hi
    jsr read_byte ; handle
    pha ; save handle
    jsr read_byte ; size
    jsr read_byte
    jsr read_byte
    jsr read_byte
    pla ; restore handle
    clc
    rts

; Read chunk from handle A into buffer at X(lo) Y(hi). Returns bytes read in A.
read_chunk:
    pha ; save handle
    stx t_ptr_temp
    sty t_ptr_temp+1
    
    lda #$FF
    sta VIA_DDRA
    lda #CMD_FS_READ
    jsr send_byte
    lda #3
    jsr send_byte
    pla ; restore handle
    jsr send_byte
    lda #<READ_CHUNK_SIZE
    jsr send_byte
    lda #>READ_CHUNK_SIZE
    jsr send_byte
    
    lda #$00
    sta VIA_DDRA
    jsr read_byte ; Status
    cmp #STATUS_OK
    beq @read_ok
    
    ; Error
    jsr read_byte
    jsr read_byte
    lda #0
    rts
@read_ok:
    jsr read_byte ; len lo
    sta t_temp_len ; temp
    jsr read_byte ; len hi
    
    ldx #0
    ldy #0
@read_loop:
    cpy t_temp_len
    beq @done
    jsr read_byte
    sta (t_ptr_temp), y
    iny
    jmp @read_loop
@done:
    lda t_temp_len
    rts

close_file:
    pha ; save handle
    lda #$FF
    sta VIA_DDRA
    lda #CMD_FS_CLOSE
    jsr send_byte
    lda #1
    jsr send_byte
    pla ; restore handle
    jsr send_byte
    
    lda #$00
    sta VIA_DDRA
    jsr read_byte
    jsr read_byte
    jsr read_byte
    rts

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

.segment "RODATA"
msg_usage:      .asciiz "Usage: DIFF <file1> <file2>"
msg_fail_open:  .asciiz "Error: Could not open file"
msg_identical:  .asciiz "Files are identical"
msg_diff_size:  .asciiz "Files differ in size"
msg_diff_at:    .asciiz "Diff at "
msg_vs:         .asciiz " vs "