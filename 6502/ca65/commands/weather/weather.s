; weather.s - Fetch weather from wttr.in
; Usage: WEATHER
;        WEATHER <location>
;        WEATHER SETDEFAULT <location>

.include "pico_def.inc"

.import read_byte, send_byte, pico_send_request
.import CMD_ID, ARG_LEN, ARG_BUFF, LAST_STATUS, RESP_LEN, RESP_BUFF

; ---------------------------------------------------------------------------
; System calls & Constants
; ---------------------------------------------------------------------------
OUTCH = $FFEF
CRLF  = $FED1
INPUT_BUFFER = $0300
ACIA_DATA = $5000

; ---------------------------------------------------------------------------
; Zero Page (Transient Safe Area $58-$5F)
; ---------------------------------------------------------------------------
t_arg_ptr      = $58 ; 2 bytes
t_str_ptr1     = $5A ; 2 bytes
t_len_cnt      = $5C ; 2 bytes
t_line_cnt     = $5E ; 1 byte

.segment "HEADER"
    .word $0800

.segment "CODE"
start:
    php
    pha
    txa
    pha
    tya
    pha

    ; --- Argument Parsing ---
    ; Find start of arguments after "RUN /BIN/WEATHER.BIN"
    lda #<INPUT_BUFFER
    sta t_arg_ptr
    lda #>INPUT_BUFFER
    sta t_arg_ptr+1
    jsr skip_word ; "RUN"
    jsr skip_word ; "/BIN/WEATHER.BIN"

    ; Check for SETDEFAULT
    ldy #0
    lda (t_arg_ptr), y
    cmp #'S'
    bne @get_weather
    
    lda #<str_setdefault
    sta t_str_ptr1
    lda #>str_setdefault
    sta t_str_ptr1+1
    jsr strcmp
    bne @get_weather
    jmp @do_setdefault

@get_weather:
    ; Pack arguments (if any)
    ldx #0
    ldy #0
    
    ; Check for empty args immediately
    lda (t_arg_ptr), y
    beq @no_args

@arg_loop:
    lda (t_arg_ptr), y
    beq @args_packed
    sta ARG_BUFF, x
    inx
    iny
    jmp @arg_loop
@args_packed:
    sta ARG_BUFF, x
    inx
    stx ARG_LEN
    jmp @send_cmd

@no_args:
    stx ARG_LEN ; X is 0

@send_cmd:
    ; --- Send Command & Receive Stream ---
    lda #<msg_fetching
    sta t_str_ptr1
    lda #>msg_fetching
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF

    lda #$FF
    sta VIA_DDRA ; Port A to output

    lda #CMD_NET_WEATHER
    jsr send_byte
    lda ARG_LEN
    jsr send_byte
    ldx #0
@send_args_loop:
    cpx ARG_LEN
    beq @send_args_done
    lda ARG_BUFF, x
    jsr send_byte
    inx
    jmp @send_args_loop
@send_args_done:

    lda #$00
    sta VIA_DDRA

    ; Wait for initial response from Pico (Status + 2 bytes Len)
    jsr read_byte
    pha             ; Save status
    jsr read_byte   ; consume len_lo
    jsr read_byte   ; consume len_hi
    pla             ; Restore status
    cmp #STATUS_OK
    bne @stream_fail

    lda #0
    sta t_line_cnt

@read_frame_len:
    jsr read_byte
    sta t_len_cnt
    jsr read_byte
    sta t_len_cnt+1

    lda t_len_cnt
    ora t_len_cnt+1
    beq @stream_done

@read_frame_data:
    jsr read_byte
    jsr paging_outch

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

@stream_fail:
    lda #<msg_fail
    sta t_str_ptr1
    lda #>msg_fail
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    jmp @done_stream

@stream_done:
@done_stream:
    lda #$FF
    sta VIA_DDRA
    jmp done

@do_setdefault:
    ; Skip "SETDEFAULT" word
    jsr skip_word

    ; Pack location into ARG_BUFF
    ldx #0
    ldy #0
@pack_loop:
    lda (t_arg_ptr), y
    beq @pack_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @pack_loop
@pack_done:
    stx ARG_LEN

    ; --- Write /etc/weather.cfg ---
    ; 1. Open file
    lda #CMD_FS_OPEN
    sta CMD_ID
    ldx #0
@copy_cfg_path:
    lda str_cfg_path, x
    sta ARG_BUFF, x
    beq @path_copied
    inx
    jmp @copy_cfg_path
@path_copied:
    stx ARG_LEN
    jsr pico_send_request
    lda LAST_STATUS
    bne @cfg_fail
    lda RESP_BUFF ; Get handle
    pha

    ; 2. Write data
    lda #CMD_FS_WRITE
    sta CMD_ID
    pla
    sta ARG_BUFF ; Handle
    ldx #1
    ldy #0
@copy_data:
    lda ARG_LEN
    cpy ARG_LEN
    beq @data_copied
    lda ARG_BUFF, y
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_data
@data_copied:
    stx ARG_LEN
    jsr pico_send_request
    lda LAST_STATUS
    bne @cfg_fail

    ; 3. Close file
    lda #CMD_FS_CLOSE
    sta CMD_ID
    lda RESP_BUFF ; Handle from OPEN
    sta ARG_BUFF
    lda #1
    sta ARG_LEN
    jsr pico_send_request

    lda #<msg_saved
    sta t_str_ptr1
    lda #>msg_saved
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    jmp done

@cfg_fail:
    lda #<msg_fail
    sta t_str_ptr1
    lda #>msg_fail
    sta t_str_ptr1+1
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

; --- Helpers ---
skip_word:
    ldy #0
@skip_chars:
    lda (t_arg_ptr), y
    beq @done
    cmp #' '
    beq @found_space
    iny
    jmp @skip_chars
@found_space:
@skip_spaces:
    iny
    lda (t_arg_ptr), y
    beq @done
    cmp #' '
    beq @skip_spaces
@done:
    tya
    clc
    adc t_arg_ptr
    sta t_arg_ptr
    lda #0
    adc t_arg_ptr+1
    sta t_arg_ptr+1
    rts

strcmp:
    ldy #0
@loop:
    lda (t_str_ptr1), y
    beq @match_prefix     ; End of keyword -> Match!
    cmp (t_arg_ptr), y
    bne @no_match
    iny
    jmp @loop
@match_prefix:
    ; We matched the keyword. Now check if input has space or null.
    lda (t_arg_ptr), y
    beq @match
    cmp #' '
    beq @match
    ; If it continues with other chars (e.g. SETDEFAULTS), it's not a match.
@no_match:
    lda #1
    rts
@match:
    lda #0
    rts

print_string:
    ldy #0
@loop:
    lda (t_str_ptr1), y
    beq @done
    jsr OUTCH
    iny
    jmp @loop
@done:
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

check_paging:
    inc t_line_cnt
    lda t_line_cnt
    cmp #22
    bcc @done
    lda #<msg_more
    sta t_str_ptr1
    lda #>msg_more
    sta t_str_ptr1+1
    jsr print_string
@wait_key:
    lda ACIA_DATA
    beq @wait_key
    cmp #'q'
    beq @abort
    cmp #'Q'
    beq @abort
    jsr CRLF
    lda #0
    sta t_line_cnt
@done:
    rts
@abort:
    ; For now, just continue. A real abort would need a signal to the Pico.
    lda #0
    sta t_line_cnt
    jsr CRLF
    rts

.segment "RODATA"
str_setdefault: .asciiz "SETDEFAULT"
str_cfg_path:   .asciiz "/etc/weather.cfg"
msg_fetching:   .asciiz "Checking Weather..."
msg_fail:       .asciiz "Failed."
msg_saved:      .asciiz "Default location saved."
msg_more:       .asciiz "--More--"