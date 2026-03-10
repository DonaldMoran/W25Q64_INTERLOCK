; man.s - Display manual pages
; Usage: MAN <command>

.include "../../common/pico_def.inc"

.import read_byte, send_byte, pico_send_request
.import ARG_BUFF, CMD_ID, ARG_LEN, LAST_STATUS, RESP_BUFF, RESP_LEN

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
t_line_cnt   = $5B ; 1 byte
t_read_len   = $5C ; 1 byte

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

    ; Sanitize CPU
    cld
    sei

    ; Initialize variables
    lda #0
    sta t_line_cnt

    ; -----------------------------------------------------------------------
    ; Parse Arguments
    ; -----------------------------------------------------------------------
    lda #<INPUT_BUFFER
    sta t_ptr_temp
    lda #>INPUT_BUFFER
    sta t_ptr_temp+1

    ; Skip "RUN" and "/BIN/MAN.BIN"
    jsr skip_word
    jsr skip_word

    ; Find argument
    ldy #0
    lda (t_ptr_temp), y
    bne @arg_found
    jmp usage_error

@arg_found:
    ; Construct path: /MAN/<ARG>.man
    ldx #0
    
    ; Copy "/MAN/"
    ldy #0
@copy_prefix:
    lda str_prefix, y
    beq @prefix_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_prefix
@prefix_done:

    ; Copy Argument (Command Name) and convert to lowercase
    ldy #0
@copy_arg:
    lda (t_ptr_temp), y
    beq @arg_done
    cmp #' '
    beq @arg_done
    
    ; Convert A-Z to a-z
    cmp #'A'
    bcc @store_char
    cmp #'Z'+1
    bcs @store_char
    adc #32
@store_char:
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_arg
@arg_done:

    ; Copy ".man" suffix
    ldy #0
@copy_suffix:
    lda str_suffix, y
    beq @suffix_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_suffix
@suffix_done:
    
    lda #0
    sta ARG_BUFF, x ; Null terminate
    inx
    lda #1          ; Mode 1 = Read Only
    sta ARG_BUFF, x
    inx
    stx ARG_LEN

    ; -----------------------------------------------------------------------
    ; Open File
    ; -----------------------------------------------------------------------
    lda #CMD_FS_OPEN
    sta CMD_ID
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @open_ok
    
    ; Error message
    lda #<msg_not_found
    sta t_ptr_temp
    lda #>msg_not_found
    sta t_ptr_temp+1
    jsr print_string_crlf
    jmp done

@open_ok:
    ; Get handle from response (first byte of payload)
    lda RESP_BUFF
    sta t_handle

    ; -----------------------------------------------------------------------
    ; Read Loop
    ; -----------------------------------------------------------------------
@read_loop:
    lda #CMD_FS_READ
    sta CMD_ID
    
    ; Args: [Handle] [LenLO] [LenHI]
    lda t_handle
    sta ARG_BUFF
    lda #<READ_CHUNK_SIZE
    sta ARG_BUFF+1
    lda #>READ_CHUNK_SIZE
    sta ARG_BUFF+2
    lda #3
    sta ARG_LEN
    
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    bne close_file
    
    ; Check length read
    lda RESP_LEN
    ora RESP_LEN+1
    beq close_file ; 0 bytes read = EOF
    
    ; Print buffer
    lda RESP_LEN
    sta t_read_len
    
    ldx #0
@print_loop:
    cpx t_read_len
    beq @read_loop
    
    lda RESP_BUFF, x
    jsr paging_outch
    inx
    jmp @print_loop

close_file:
    lda #CMD_FS_CLOSE
    sta CMD_ID
    lda t_handle
    sta ARG_BUFF
    lda #1
    sta ARG_LEN
    jsr pico_send_request

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
    jsr print_string_crlf
    jmp done

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

print_string_crlf:
    jsr print_string
    jsr CRLF
    rts

paging_outch:
    pha
    jsr OUTCH
    pla
    cmp #$0A ; Newline
    bne @done
    
    inc t_line_cnt
    lda t_line_cnt
    cmp #22 ; Page size
    bcc @done
    
    ; Pause
    lda #<msg_more
    sta t_ptr_temp
    lda #>msg_more
    sta t_ptr_temp+1
    jsr print_string
    
@wait_key:
    lda ACIA_DATA
    beq @wait_key
    
    cmp #'q'
    beq @quit
    cmp #'Q'
    beq @quit
    
    jsr CRLF
    lda #0
    sta t_line_cnt
@done:
    rts

@quit:
    ; Balance stack (pha) and pop return address from jsr
    pla ; for pha
    pla ; for PC lo
    pla ; for PC hi
    jmp close_file

.segment "RODATA"
str_prefix:    .asciiz "/MAN/"
str_suffix:    .asciiz ".man"
msg_usage:     .asciiz "Usage: MAN <command>"
msg_not_found: .asciiz "No manual entry found."
msg_more:      .asciiz "--More--"