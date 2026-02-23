; date.s - Transient DATE command
; Location: 6502/ca65/commands/date/date.s

; ---------------------------------------------------------------------------
; External symbols
; ---------------------------------------------------------------------------
.include "pico_def.inc"

.import pico_send_request
.import CMD_ID, ARG_LEN, ARG_BUFF, LAST_STATUS, RESP_LEN, RESP_BUFF

; ---------------------------------------------------------------------------
; System calls
; ---------------------------------------------------------------------------
OUTCH = $FFEF    ; Print character in A
CRLF  = $FED1    ; Print CR/LF

; ---------------------------------------------------------------------------
; Zero page (USE ONLY $58-$5F)
; ---------------------------------------------------------------------------
t_arg_ptr    = $58  ; 2 bytes - Argument pointer
t_str_ptr1   = $5A  ; 2 bytes - String pointer 1
t_ptr_temp   = $5E  ; 2 bytes - Temporary pointer

; ---------------------------------------------------------------------------
; HEADER - MUST be first
; ---------------------------------------------------------------------------
.segment "HEADER"
    .word $0800        ; Load at $0800

; ---------------------------------------------------------------------------
; CODE - Program starts here
; ---------------------------------------------------------------------------
.segment "CODE"

start:
    ; Preserve registers
    php
    pha
    txa
    pha
    tya
    pha

    ; Check for arguments
    ; The shell passes arguments in the input buffer, but transient programs
    ; don't have direct access to the shell's parsing logic.
    ; However, for simplicity in this first version, we will assume:
    ; If the user typed "DATE", we get time.
    ; If the user typed "DATE <ARGS>", we set time.
    ; Since we don't have the shell's argument parser exposed, we will
    ; rely on the fact that the shell copies the command line to $0300.
    ; We need to skip "DATE " to find arguments.
    
    ; Simple parser: Skip "RUN" and "FILENAME" to find args
    ldx #0
    
    ; 1. Skip "RUN"
@skip_word_1:
    lda $0300, x ; Read from Shell Input Buffer
    bne @check_space_1
    jmp @get_time ; EOL
@check_space_1:
    cmp #' '
    beq @found_space_1
    inx
    jmp @skip_word_1
@found_space_1:
    inx
    lda $0300, x
    bne @check_space_1_b
    jmp @get_time
@check_space_1_b:
    cmp #' '
    beq @found_space_1 ; Skip multiple spaces

    ; 2. Skip Filename (e.g. "/BIN/DATE.BIN")
@skip_word_2:
    lda $0300, x
    bne @check_space_2
    jmp @get_time
@check_space_2:
    cmp #' '
    beq @found_space_2
    inx
    jmp @skip_word_2
@found_space_2:
    inx
    lda $0300, x
    bne @check_space_2_b
    jmp @get_time
@check_space_2_b:
    cmp #' '
    beq @found_space_2 ; Skip multiple spaces
    
    ; Clear ARG_BUFF first to avoid garbage
    ldy #0
    lda #0
@clear_arg_buff:
    sta ARG_BUFF, y
    iny
    bne @clear_arg_buff
    
    ; Found argument start at index X
    ; Copy argument to ARG_BUFF
    ldy #0
@copy_arg:
    lda $0300, x
    beq @arg_done
    sta ARG_BUFF, y
    inx
    iny
    jmp @copy_arg
@arg_done:
    sta ARG_BUFF, y ; Null terminate
    sty ARG_LEN
    
    ; --- Check for NTP ---
    lda ARG_BUFF
    and #$5F ; To Upper (Force 7-bit)
    cmp #'N'
    bne @not_ntp
    lda ARG_BUFF+1
    and #$5F ; To Upper
    cmp #'T'
    bne @not_ntp
    lda ARG_BUFF+2
    and #$5F ; To Upper
    cmp #'P'
    bne @not_ntp
    
    ; Ensure it is "NTP" or "NTP " (not "NTP2026")
    lda ARG_BUFF+3
    beq @is_ntp      ; End of string
    cmp #' '
    beq @is_ntp
@not_ntp:
    jmp @set_time
    
@is_ntp:
    ; It is NTP. Check for offset argument (e.g. "NTP -5")
    ldx #3
@find_offset:
    lda ARG_BUFF, x
    beq @no_offset
    cmp #' '
    bne @found_offset_char
    inx
    jmp @find_offset
    
@found_offset_char:
    ; Shift offset string to beginning of ARG_BUFF
    ldy #0
@shift_offset:
    lda ARG_BUFF, x
    sta ARG_BUFF, y
    beq @offset_done
    inx
    iny
    jmp @shift_offset
@offset_done:
    sty ARG_LEN
    jmp @do_ntp

@no_offset:
    lda #0
    sta ARG_LEN
    ; Fall through to @do_ntp

@do_ntp:
    lda #CMD_NET_TIME
    sta CMD_ID
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @print_time_ntp
    
    lda #<msg_ntp_fail
    sta t_str_ptr1
    lda #>msg_ntp_fail
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    jmp done

@print_time_ntp:
    jmp @print_time

@set_time:
    ; --- Set Time ---
    lda #CMD_SYS_SET_TIME
    sta CMD_ID
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @success
    
    lda #<msg_invalid_date
    sta t_str_ptr1
    lda #>msg_invalid_date
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    jmp done

@success:
    jmp done

    ; --- Get Time ---
@get_time:
    lda #CMD_SYS_GET_TIME
    sta CMD_ID
    lda #0
    sta ARG_LEN
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @print_time
    
    lda #<msg_rtc_err
    sta t_str_ptr1
    lda #>msg_rtc_err
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    jmp done

@print_time:
    ; Response is in RESP_BUFF (imported from pico_lib)
    ; Null terminate RESP_BUFF based on RESP_LEN to avoid printing garbage
    ldy RESP_LEN
    lda RESP_LEN+1
    bne @do_print ; If length > 255, skip termination (unlikely for date)
    lda #0
    sta RESP_BUFF, y
@do_print:
    ; We need to print it. RESP_BUFF is at a known location.
    ; We can use a simple loop since we know it's null-terminated or length-bounded.
    ; But wait, print_string expects a pointer.
    ; Let's just assume RESP_BUFF is exported by pico_lib.s
    ; Actually, we can just use the address directly if we know it, 
    ; or better, use the helper.
    ; For now, let's just assume RESP_BUFF is available.
    ; (It is imported in the header)
    
    ; We need to implement a print_response or similar here, 
    ; or just print the buffer directly.
    ; Let's implement a simple print loop for the response.
    ; The response format from Pico for GET_TIME is a string.
    
    ; We need to know where RESP_BUFF is. It's in BSS of pico_lib.
    ; Since we link against pico_lib.o, we can access it.
    ; However, we need the address.
    ; Let's use a trick: The response is in the buffer pointed to by RESP_BUFF symbol.
    
    ; Actually, we can just use the print_string helper if we load the address of RESP_BUFF.
    ; But RESP_BUFF is a label for the memory location.
    
    ; Wait, RESP_BUFF is defined in pico_lib.s BSS.
    ; We can just load its address.
    
    lda #<RESP_BUFF
    sta t_str_ptr1
    lda #>RESP_BUFF
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

; ---------------------------------------------------------------------------
; Helper: Print null-terminated string
; ---------------------------------------------------------------------------
print_string:
    phy
    ldy #0
@loop:
    lda (t_str_ptr1), y
    beq @done
    jsr OUTCH
    iny
    jmp @loop
@done:
    ply
    rts

; ---------------------------------------------------------------------------
; RODATA
; ---------------------------------------------------------------------------
.segment "RODATA"

msg_invalid_date: .asciiz "INVALID DATE"
msg_ntp_fail:    .asciiz "NTP ERROR"
msg_rtc_err:     .asciiz "RTC NOT SET"
