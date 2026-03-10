; hex.s - Hex Dump Command
; Usage: HEX <filename>

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
t_count      = $5A ; 2 bytes (Remaining bytes)
t_offset     = $5C ; 2 bytes (Display offset)
; $5E/$5F are used for CWD pointer on entry, reused for paging/index later
t_cwd_ptr    = $5E ; 2 bytes (On entry)
t_line_cnt   = $5E ; 1 byte (Paging)
t_hex_idx    = $5F ; 1 byte (Index 0-15)

; ---------------------------------------------------------------------------
; System calls
; ---------------------------------------------------------------------------
OUTCH  = $FFEF
CRLF   = $FED1
OUTHEX = $FFDC

.segment "HEADER"
    .word $0800

.segment "BSS"
line_buf:   .res 16

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

    ; Initialize non-overlapping variables
    lda #0
    sta t_offset
    sta t_offset+1

    ; -----------------------------------------------------------------------
    ; Parse Arguments
    ; -----------------------------------------------------------------------
    lda #<INPUT_BUFFER
    sta t_ptr_temp
    lda #>INPUT_BUFFER
    sta t_ptr_temp+1

    ; Skip "RUN" and "/BIN/HEX.BIN"
    jsr skip_word
    jsr skip_word

    ; Check for argument
    ldy #0
    lda (t_ptr_temp), y
    bne @arg_found
    
    ; No argument error
    lda #<msg_usage
    sta t_ptr_temp
    lda #>msg_usage
    sta t_ptr_temp+1
    jsr print_string
    jsr CRLF
    jmp done

@arg_found:
    ; Resolve path (reuse logic from catalog.s)
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
    jmp @copy_arg_loop

@finish_arg:
    sta ARG_BUFF, x ; Null terminate
    stx t_ptr_temp  ; Save length temporarily (low byte)

    ; -----------------------------------------------------------------------
    ; Initialize Overlapping Variables
    ; -----------------------------------------------------------------------
    ; Now that we are done with t_cwd_ptr ($5E), we can use t_line_cnt ($5E)
    lda #0
    sta t_line_cnt
    sta t_hex_idx

    ; -----------------------------------------------------------------------
    ; Send Command (CMD_FS_LOADMEM)
    ; -----------------------------------------------------------------------
    lda #$FF
    sta VIA_DDRA

    lda #CMD_FS_LOADMEM
    jsr send_byte
    
    lda t_ptr_temp ; Length
    jsr send_byte

    ldx #0
    lda t_ptr_temp
    beq @args_done
@send_args:
    lda ARG_BUFF, x
    jsr send_byte
    inx
    cpx t_ptr_temp
    bne @send_args
@args_done:

    ; -----------------------------------------------------------------------
    ; Read Response
    ; -----------------------------------------------------------------------
    lda #$00
    sta VIA_DDRA

    jsr read_byte   ; Status
    cmp #STATUS_OK
    beq @status_ok
    
    ; Error
    jsr read_byte   ; Consume len lo
    jsr read_byte   ; Consume len hi
    
    lda #<msg_fail
    sta t_ptr_temp
    lda #>msg_fail
    sta t_ptr_temp+1
    jsr print_string
    jsr CRLF
    jmp done

@status_ok:
    jsr read_byte   ; Len Lo
    sta t_count
    jsr read_byte   ; Len Hi
    sta t_count+1

    jsr CRLF

    ; -----------------------------------------------------------------------
    ; Stream Loop
    ; -----------------------------------------------------------------------
@stream_loop:
    lda t_count
    ora t_count+1
    beq @stream_done

    ; Check if start of line
    lda t_hex_idx
    bne @read_byte
    
    ; Print Offset
    lda t_offset+1
    jsr OUTHEX
    lda t_offset
    jsr OUTHEX
    lda #':'
    jsr paging_outch
    lda #' '
    jsr paging_outch

@read_byte:
    jsr read_byte
    
    ; Save in line buffer
    ldx t_hex_idx
    sta line_buf, x
    
    ; Print Hex
    jsr OUTHEX
    lda #' '
    jsr paging_outch
    
    ; Increment indices
    inc t_hex_idx
    
    ; Decrement file counter
    lda t_count
    bne @dec_lo
    dec t_count+1
@dec_lo:
    dec t_count
    
    ; Check if line full (16 bytes)
    lda t_hex_idx
    cmp #16
    bne @stream_loop
    
    ; Line full, print ASCII
    jsr print_ascii_line
    
    ; Update offset
    clc
    lda t_offset
    adc #16
    sta t_offset
    lda t_offset+1
    adc #0
    sta t_offset+1
    
    lda #0
    sta t_hex_idx
    
    jmp @stream_loop

@stream_done:
    ; Handle partial line
    lda t_hex_idx
    beq @finish
    
    ; Pad spaces
    ; Spaces needed = (16 - t_hex_idx) * 3
    lda #16
    sec
    sbc t_hex_idx
    tax
@pad_loop:
    lda #' '
    jsr paging_outch
    jsr paging_outch
    jsr paging_outch
    dex
    bne @pad_loop
    
    jsr print_ascii_line

@finish:
    lda #$FF
    sta VIA_DDRA

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
; Helpers
; ---------------------------------------------------------------------------

print_ascii_line:
    lda #'|'
    jsr paging_outch
    ldx #0
@ascii_loop:
    cpx t_hex_idx
    beq @ascii_done
    lda line_buf, x
    ; Filter non-printable
    cmp #$20
    bcc @dot
    cmp #$7F
    bcs @dot
    jmp @pr
@dot:
    lda #'.'
@pr:
    jsr paging_outch
    inx
    jmp @ascii_loop
@ascii_done:
    lda #'|'
    jsr paging_outch
    jsr paging_crlf
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
    pha
    phy
    ldy #0
@loop:
    lda (t_ptr_temp), y
    beq @ps_done
    jsr OUTCH
    iny
    jmp @loop
@ps_done:
    ply
    pla
    rts

paging_outch:
    pha
    jsr OUTCH
    pla
    cmp #$0A
    bne @done
    jsr check_paging
@done:
    rts

paging_crlf:
    lda #$0D
    jsr paging_outch
    lda #$0A
    jsr paging_outch
    rts

check_paging:
    inc t_line_cnt
    lda t_line_cnt
    cmp #22
    bcc @done
    
    lda #<msg_more
    sta t_ptr_temp
    lda #>msg_more
    sta t_ptr_temp+1
    jsr print_string
    
@wait_key:
    lda ACIA_DATA
    beq @wait_key
    
    lda #$0D
    jsr OUTCH
    lda #$0A
    jsr OUTCH
    
    lda #0
    sta t_line_cnt
@done:
    rts

.segment "RODATA"
msg_usage: .asciiz "Usage: HEX <filename>"
msg_fail:  .asciiz "Error: File not found or read error"
msg_more:  .asciiz "--More--"