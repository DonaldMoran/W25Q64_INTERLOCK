; wc.s - Word Count (lines, words, chars)
; Usage: WC <filename>

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
t_handle     = $5A ; 1 byte
t_bytes_read = $5B ; 1 byte
t_in_word    = $5C ; 1 byte
t_cwd_ptr    = $5E ; 2 bytes (passed by shell)

; Overlapping ZP for printing at the end
t_val32      = $5C ; 4 bytes ($5C-$5F), overlaps t_in_word, t_cwd_ptr

; ---------------------------------------------------------------------------
; System calls
; ---------------------------------------------------------------------------
OUTCH  = $FFEF
CRLF   = $FED1

.segment "HEADER"
    .word $0800

.segment "BSS"
read_buf:   .res READ_CHUNK_SIZE
count_lines:.res 4
count_words:.res 4
count_chars:.res 4
filename:   .res 64 ; Store filename for display

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

    ; Initialize counters
    lda #0
    sta count_lines
    sta count_lines+1
    sta count_lines+2
    sta count_lines+3
    
    sta count_words
    sta count_words+1
    sta count_words+2
    sta count_words+3
    
    sta count_chars
    sta count_chars+1
    sta count_chars+2
    sta count_chars+3
    
    sta t_in_word ; False

    ; -----------------------------------------------------------------------
    ; Parse Arguments
    ; -----------------------------------------------------------------------
    lda #<INPUT_BUFFER
    sta t_ptr_temp
    lda #>INPUT_BUFFER
    sta t_ptr_temp+1

    ; Skip "RUN" and "/BIN/WC.BIN"
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
    ; Save filename for display later
    ldx #0
@save_name:
    lda (t_ptr_temp), y
    beq @save_name_done
    cmp #' '
    beq @save_name_done
    sta filename, x
    iny
    inx
    cpx #63
    bcc @save_name
@save_name_done:
    lda #0
    sta filename, x

    ; Resolve path
    ; Check if absolute path (starts with /)
    ldy #0
    lda (t_ptr_temp), y
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
    ; Send CMD_FS_READ
    lda #$FF
    sta VIA_DDRA
    
    lda #CMD_FS_READ
    jsr send_byte
    
    lda #3          ; Arg len (Handle + 2 byte len)
    jsr send_byte
    
    lda t_handle
    jsr send_byte
    
    lda #<READ_CHUNK_SIZE
    jsr send_byte
    lda #>READ_CHUNK_SIZE
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
    ; Ignore high byte of length (chunk size < 256)
    
    ; Check if EOF (len == 0)
    lda t_bytes_read
    beq @close_file_drain ; Done
    
    ; Read Data into buffer
    ldx #0
@data_loop:
    jsr read_byte
    sta read_buf, x
    inx
    cpx t_bytes_read
    bne @data_loop
    
    lda #$FF
    sta VIA_DDRA
    
    ; Process Buffer
    ldx #0
@process_loop:
    cpx t_bytes_read
    beq @read_loop ; Next chunk
    
    lda read_buf, x
    
    ; 1. Count Char
    inc count_chars
    bne @inc_char_done
    inc count_chars+1
    bne @inc_char_done
    inc count_chars+2
    bne @inc_char_done
    inc count_chars+3
@inc_char_done:

    ; 2. Count Line
    cmp #$0A ; Newline
    bne @check_word
    inc count_lines
    bne @inc_line_done
    inc count_lines+1
    bne @inc_line_done
    inc count_lines+2
    bne @inc_line_done
    inc count_lines+3
@inc_line_done:

@check_word:
    ; 3. Count Word
    ; Is whitespace? (Space, Tab, CR, LF)
    cmp #' '
    beq @is_space
    cmp #$09 ; Tab
    beq @is_space
    cmp #$0D ; CR
    beq @is_space
    cmp #$0A ; LF
    beq @is_space
    
    ; Not whitespace
    lda t_in_word
    bne @next_char ; Already in word
    
    ; Start of new word
    lda #1
    sta t_in_word
    inc count_words
    bne @inc_word_done
    inc count_words+1
    bne @inc_word_done
    inc count_words+2
    bne @inc_word_done
    inc count_words+3
@inc_word_done:
    jmp @next_char

@is_space:
    lda #0
    sta t_in_word
    
@next_char:
    inx
    jmp @process_loop

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

    ; Print Results
    jsr CRLF
    
    lda #<count_lines
    jsr print_dec_32
    lda #' '
    jsr OUTCH
    
    lda #<count_words
    jsr print_dec_32
    lda #' '
    jsr OUTCH
    
    lda #<count_chars
    jsr print_dec_32
    lda #' '
    jsr OUTCH
    
    lda #<filename
    sta t_ptr_temp
    lda #>filename
    sta t_ptr_temp+1
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

; ---------------------------------------------------------------------------
; Helper: Print 32-bit unsigned decimal.
; In: A contains low byte of address of the 4-byte number.
;     High byte is assumed to be >BSS segment start.
; ---------------------------------------------------------------------------
print_dec_32:
    sta t_ptr_temp
    lda #>count_lines ; High byte is same for all counters in BSS
    sta t_ptr_temp+1

    ; Copy value from (t_ptr_temp) to t_val32
    ldy #0
    lda (t_ptr_temp),y
    sta t_val32+0
    iny
    lda (t_ptr_temp),y
    sta t_val32+1
    iny
    lda (t_ptr_temp),y
    sta t_val32+2
    iny
    lda (t_ptr_temp), y
    sta t_val32+3

    ; Now print from t_val32 (adapted from df.s)
    ldx #10 ; Max 10 digits for 32-bit
@outer_loop:
    ldy #32 ; 32 bits to divide
    lda #0  ; Remainder
@inner_loop:
    asl t_val32+0
    rol t_val32+1
    rol t_val32+2
    rol t_val32+3
    rol a
    cmp #10
    bcc @no_sub
    sbc #10
    inc t_val32+0 ; Set quotient bit
@no_sub:
    dey
    bne @inner_loop
    
    pha ; Save digit
    dex
    bne @outer_loop

    ; Print digits
    ldx #10
    ldy #0 ; Flag to skip leading zeros
@print_loop:
    pla
    ora #$30
    cmp #'0'
    bne @not_zero
    cpx #1 ; Is it the last digit?
    beq @force_print
    cpy #0 ; Is it a leading zero?
    beq @skip_print ; Yes, skip
@force_print:
@not_zero:
    ldy #1 ; Found a non-zero digit
    jsr OUTCH
@skip_print:
    dex
    bne @print_loop
    rts

.segment "RODATA"
msg_usage: .asciiz "Usage: WC <filename>"
msg_fail:  .asciiz "Error: File not found"