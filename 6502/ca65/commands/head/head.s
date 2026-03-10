; head.s - Print first 10 lines of a file
; Usage: HEAD <filename>

.include "../../common/pico_def.inc"

.import read_byte, send_byte
.import ARG_BUFF

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
INPUT_BUFFER = $0300
ACIA_DATA    = $5000
READ_CHUNK_SIZE = 64

; ---------------------------------------------------------------------------
; Zero Page (Transient Safe Area $58-$5F)
; ---------------------------------------------------------------------------
t_ptr_temp   = $58 ; 2 bytes
t_handle     = $5A ; 1 byte
t_lines      = $5B ; 1 byte
t_bytes_read = $5C ; 2 bytes
t_cwd_ptr    = $5E ; 2 bytes (passed by shell, reused after parsing)

; ---------------------------------------------------------------------------
; System calls
; ---------------------------------------------------------------------------
OUTCH  = $FFEF
CRLF   = $FED1

.segment "HEADER"
    .word $0800

.segment "BSS"
read_buf:   .res 256

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
    lda #10
    sta t_lines

    ; -----------------------------------------------------------------------
    ; Parse Arguments
    ; -----------------------------------------------------------------------
    lda #<INPUT_BUFFER
    sta t_ptr_temp
    lda #>INPUT_BUFFER
    sta t_ptr_temp+1

    ; Skip "RUN" and "/BIN/HEAD.BIN"
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
    ; Resolve path
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
    lda #0
    sta ARG_BUFF, x ; Null terminate
    inx
    lda #1          ; Mode 1 = Read Only
    sta ARG_BUFF, x
    inx
    stx t_ptr_temp  ; Save length temporarily (low byte)

    ; -----------------------------------------------------------------------
    ; Open File (CMD_FS_OPEN)
    ; -----------------------------------------------------------------------
    lda #$FF
    sta VIA_DDRA

    lda #CMD_FS_OPEN
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

    ; Read Response
    lda #$00
    sta VIA_DDRA

    jsr read_byte   ; Status
    cmp #STATUS_OK
    beq @open_ok
    
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

@open_ok:
    jsr read_byte   ; Len Lo (5)
    jsr read_byte   ; Len Hi (0)
    
    jsr read_byte   ; Handle
    sta t_handle
    
    ; Consume Size (4 bytes)
    jsr read_byte
    jsr read_byte
    jsr read_byte
    jsr read_byte
    
    lda #$FF
    sta VIA_DDRA

    ; -----------------------------------------------------------------------
    ; Read Loop
    ; -----------------------------------------------------------------------
@read_loop:
    lda t_lines
    beq @close_file

    ; Send CMD_FS_READ
    lda #$FF
    sta VIA_DDRA
    
    lda #CMD_FS_READ
    jsr send_byte
    
    lda #3          ; Arg len (Handle + 2 byte len)
    jsr send_byte
    
    lda t_handle
    jsr send_byte
    
    lda #READ_CHUNK_SIZE
    jsr send_byte
    lda #0
    jsr send_byte
    
    ; Read Response
    lda #$00
    sta VIA_DDRA
    
    jsr read_byte   ; Status
    cmp #STATUS_OK
    beq @read_ok
    
    ; Error reading
    jsr read_byte ; len lo
    jsr read_byte ; len hi
    jmp @close_file

@read_ok:
    jsr read_byte   ; Len Lo
    sta t_bytes_read
    jsr read_byte   ; Len Hi
    sta t_bytes_read+1
    
    ; Check if EOF (len == 0)
    lda t_bytes_read
    ora t_bytes_read+1
    beq @close_file_drain ; Done
    
    ; Read Data into buffer
    ldx #0
@data_loop:
    jsr read_byte
    sta read_buf, x
    inx
    
    ; Decrement count
    lda t_bytes_read
    bne @dec_lo
    dec t_bytes_read+1
@dec_lo:
    dec t_bytes_read
    
    lda t_bytes_read
    ora t_bytes_read+1
    bne @data_loop
    
    lda #$FF
    sta VIA_DDRA
    
    ; Process Buffer
    stx t_bytes_read ; Save count read (X)
    ldx #0
@print_loop:
    cpx t_bytes_read
    beq @read_loop ; Next chunk
    
    lda read_buf, x
    jsr OUTCH
    
    cmp #$0A ; Newline
    bne @next_char
    dec t_lines
    beq @close_file ; Done
    
@next_char:
    inx
    jmp @print_loop

@close_file_drain:
    lda #$FF
    sta VIA_DDRA
    ; Fall through

@close_file:
    ; Send CMD_FS_CLOSE
    lda #$FF
    sta VIA_DDRA
    
    lda #CMD_FS_CLOSE
    jsr send_byte
    
    lda #1 ; Arg len
    jsr send_byte
    
    lda t_handle
    jsr send_byte
    
    ; Read Response
    lda #$00
    sta VIA_DDRA
    
    jsr read_byte ; Status
    jsr read_byte ; Len Lo
    jsr read_byte ; Len Hi
    
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

.segment "RODATA"
msg_usage: .asciiz "Usage: HEAD <filename>"
msg_fail:  .asciiz "Error: File not found"