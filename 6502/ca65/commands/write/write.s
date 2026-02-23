; write.s - Simple text editor (FINAL VERSION with special key handling)
; Location: 6502/ca65/commands/write/write.s

; ---------------------------------------------------------------------------
; External symbols
; ---------------------------------------------------------------------------
.import pico_send_request, send_byte, read_byte
.import CMD_ID, ARG_LEN, ARG_BUFF, LAST_STATUS, RESP_LEN, RESP_BUFF

; ---------------------------------------------------------------------------
; System calls & Constants
; ---------------------------------------------------------------------------
OUTCH = $FFEF    ; Print character in A
CRLF  = $FED1    ; Print CR/LF
CHRIN = $A231    ; Input character from console

VIA_DDRA = $6003 ; Data Direction Register A

CMD_FS_SAVEMEM = $23
STATUS_OK      = $00

INPUT_BUFFER   = $0300

; ---------------------------------------------------------------------------
; Zero page (USE ONLY $58-$5F)
; ---------------------------------------------------------------------------
t_arg_ptr    = $58  ; 2 bytes - Argument pointer
t_str_ptr1   = $5A  ; 2 bytes - Text Buffer Pointer (current position)
t_str_ptr2   = $5C  ; 2 bytes - String Printing / Streaming Pointer
t_ptr_temp   = $5E  ; 2 bytes - Temp / Length Counter

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
TEXT_BUFFER_SIZE = 4096  ; 4KB text buffer

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

    ; Save CWD pointer passed from shell in $5E/$5F
    lda t_ptr_temp
    sta cwd_ptr
    lda t_ptr_temp+1
    sta cwd_ptr+1

    ; Initialize text buffer pointer to start of FIXED buffer
    lda #<text_buffer_fixed
    sta t_str_ptr1
    lda #>text_buffer_fixed
    sta t_str_ptr1+1
    
    ; Clear the entire buffer at startup
    lda #<text_buffer_fixed
    sta t_str_ptr2
    lda #>text_buffer_fixed
    sta t_str_ptr2+1
    ldx #0
    ldy #0
@clear_buffer:
    tya
    sta (t_str_ptr2), y
    iny
    bne @clear_buffer
    inc t_str_ptr2+1
    inx
    cpx #(TEXT_BUFFER_SIZE / 256)  ; Clear full buffer size
    bne @clear_buffer

    ; Reset pointer to start
    lda #<text_buffer_fixed
    sta t_str_ptr1
    lda #>text_buffer_fixed
    sta t_str_ptr1+1

    ; Parse Filename Argument
    jsr parse_filename
    
    ; Initialize UI
    jsr init_ui
    
    ; --- Editor Loop ---
editor_loop:
    jsr CHRIN
    
    ; Check for escape sequences (arrow keys, function keys)
    cmp #$1B  ; ESC
    bne @check_ctrlx
    jmp handle_escape
@check_ctrlx:
    
    ; Control characters
    cmp #$18 ; Ctrl+X
    bne @check_bs
    jmp exit_check
@check_bs:
    cmp #$08 ; Backspace
    bne @check_del
    jmp handle_bs
@check_del:
    cmp #$7F ; Delete
    bne @check_enter
    jmp handle_bs
@check_enter:
    cmp #$0D ; Enter
    bne @check_tab
    jmp handle_enter
@check_tab:
    cmp #$09 ; Tab
    bne @check_lf
    jmp handle_tab
@check_lf:
    cmp #$0A ; LF (ignore, we handle with CR)
    beq editor_loop  ; This is fine if editor_loop is close
    
    cmp #$1B ; ESC (already handled)
    beq editor_loop  ; This is fine if editor_loop is close

    ; Check for other control characters (0x00-0x1F except those we handle)
    cmp #$20
    bcc editor_loop  ; This is fine if editor_loop is close

    ; Printable Char (0x20-0x7E)
    jsr store_char
    jmp editor_loop

    ; Check for other control characters (0x00-0x1F except those we handle)
    cmp #$20
    bcc editor_loop  ; Ignore other control characters

    ; Printable Char (0x20-0x7E)
    jsr store_char
    jmp editor_loop

handle_escape:
    ; Handle escape sequences (arrow keys, etc.)
    jsr CHRIN  ; Get next character (usually '[')
    cmp #'['
    bne editor_loop  ; Not an arrow key sequence
    
    jsr CHRIN  ; Get the arrow key code
    cmp #'A'   ; Up arrow
    beq @ignore_escape
    cmp #'B'   ; Down arrow
    beq @ignore_escape
    cmp #'C'   ; Right arrow
    beq @ignore_escape
    cmp #'D'   ; Left arrow
    beq @ignore_escape
    
    ; If it's not an arrow key, maybe it's a function key
    ; Just ignore it
@ignore_escape:
    jmp editor_loop

handle_tab:
    ; Handle tab - store a space or multiple spaces
    ; For simplicity, store a single space
    lda #' '
    jsr store_char
    jsr OUTCH  ; Echo the space
    jmp editor_loop

handle_bs:
    ; Check if we are at start of buffer
    lda t_str_ptr1
    cmp #<text_buffer_fixed
    bne @do_bs
    lda t_str_ptr1+1
    cmp #>text_buffer_fixed
    beq editor_loop ; At start, do nothing

@do_bs:
    ; Decrement pointer (remove last character from buffer)
    lda t_str_ptr1
    bne @dec_lo
    dec t_str_ptr1+1
@dec_lo:
    dec t_str_ptr1
    
    ; Clear the character from buffer (optional but good)
    ldy #0
    lda #0
    sta (t_str_ptr1), y
    
    ; Visual Backspace (BS, Space, BS)
    lda #$08
    jsr OUTCH
    lda #' '
    jsr OUTCH
    lda #$08
    jsr OUTCH
    jmp editor_loop

handle_enter:
    lda #$0D  ; Carriage Return
    jsr OUTCH ; Echo CR
    
    lda #$0A  ; Line Feed
    jsr store_char  ; Store LF in file
    jsr OUTCH ; Echo LF
    
    jmp editor_loop

store_char:
    ; Store character at current buffer position
    ldy #0
    sta (t_str_ptr1), y
       
    ; Increment pointer
    inc t_str_ptr1
    bne @ret
    inc t_str_ptr1+1
    
    ; Check for buffer overflow (optional)
    lda t_str_ptr1+1
    cmp #>(text_buffer_fixed + TEXT_BUFFER_SIZE)
    bcc @ret
    lda t_str_ptr1
    cmp #<(text_buffer_fixed + TEXT_BUFFER_SIZE)
    bcc @ret
    
    ; Buffer full - beep or indicator
    lda #$07  ; BEL character
    jsr OUTCH
    ; Don't increment if buffer full
    dec t_str_ptr1
    bne @ret
    dec t_str_ptr1+1
    
@ret:
    rts

exit_check:
    jsr CRLF
    lda #<save_prompt
    ldy #>save_prompt
    jsr print_str_ay
    
@ask_loop:
    jsr CHRIN
    and #$DF ; To Upper
    cmp #'N'
    beq exit_editor
    cmp #'Y'
    beq save_sequence
    cmp #$0D ; Enter (default to No)
    beq exit_editor
    jmp @ask_loop

save_sequence:
    ; Check if filename exists
    lda filename_buf
    bne @has_filename
    
    ; Ask for filename
    jsr CRLF
    lda #<filename_prompt
    ldy #>filename_prompt
    jsr print_str_ay
    
    ; Read filename
    ldy #0
@read_fname:
    jsr CHRIN
    cmp #$0D
    beq @fname_read_done
    cmp #$08  ; Backspace during filename entry
    beq @fname_bs
    cmp #$7F  ; Delete
    beq @fname_bs
    cmp #$20
    bcc @read_fname  ; Ignore other controls
    sta filename_buf, y
    ; REMOVE THIS ECHO - it's causing double printing
    ; jsr OUTCH  ; Echo
    iny
    cpy #126
    bcc @read_fname
    jmp @read_fname  ; Buffer full, just read and discard
    
@fname_bs:
    ; Handle backspace in filename entry
    cpy #0
    beq @read_fname  ; At start, ignore
    dey
    lda #$08
    jsr OUTCH
    lda #' '
    jsr OUTCH
    lda #$08
    jsr OUTCH
    jmp @read_fname
    
@fname_read_done:
    lda #0
    sta filename_buf, y
    jsr CRLF
    
    ; Check if empty
    lda filename_buf
    beq exit_editor

@has_filename:
    jsr perform_save
    ; Fall through to exit_editor
    
exit_editor:
    pla          ; Get Y
    tay
    pla          ; Get X
    tax
    pla          ; Get A
    plp          ; Get processor status
    clc
    rts

; ---------------------------------------------------------------------------
; Parse filename from command line
; ---------------------------------------------------------------------------
parse_filename:
    ldx #0
    ldy #0
    
@skip_spaces:
    lda INPUT_BUFFER, x
    beq @no_args
    cmp #' '
    bne @check_run
    inx
    bne @skip_spaces

@check_run:
    lda INPUT_BUFFER, x
    beq @no_args
    cmp #' '
    beq @found_space_1
    inx
    bne @check_run
    
@found_space_1:
    inx
    
@skip_path:
    lda INPUT_BUFFER, x
    beq @no_args
    cmp #' '
    beq @found_space_2
    inx
    bne @skip_path
    
@found_space_2:
    inx
    
@skip_filename_spaces:
    lda INPUT_BUFFER, x
    beq @no_args
    cmp #' '
    bne @copy_arg
    inx
    bne @skip_filename_spaces

@copy_arg:
    lda INPUT_BUFFER, x
    beq @arg_done
    cmp #' '
    beq @arg_done
    sta filename_buf, y
    inx
    iny
    cpy #126
    bcc @copy_arg
    
@arg_done:
    lda #0
    sta filename_buf, y
    rts

@no_args:
    lda #0
    sta filename_buf
    rts

; ---------------------------------------------------------------------------
; Initialize UI
; ---------------------------------------------------------------------------
init_ui:
    lda #<ansi_cls
    ldy #>ansi_cls
    jsr print_str_ay
    
    lda #<header_msg
    ldy #>header_msg
    jsr print_str_ay
    
    lda filename_buf
    bne @has_filename
    
    lda #<no_file_msg
    ldy #>no_file_msg
    jsr print_str_ay
    jmp @continue
    
@has_filename:
    lda #<filename_buf
    ldy #>filename_buf
    jsr print_str_ay
    
@continue:
    jsr CRLF
    
    lda #<separator_msg
    ldy #>separator_msg
    jsr print_str_ay
    jsr CRLF
    
    lda #<footer_msg
    ldy #>footer_msg
    jsr print_str_ay
    jsr CRLF
    rts

; ---------------------------------------------------------------------------
; Perform save operation
; ---------------------------------------------------------------------------
perform_save:
    ; Save current VIA state
    lda VIA_DDRA
    pha
    
    ; 1. Construct Path in ARG_BUFF
    lda filename_buf
    cmp #'/'
    beq @abs_path
    
    ; Relative path
    ldx #0
    ldy #0
    
    lda cwd_ptr
    sta t_str_ptr2
    lda cwd_ptr+1
    sta t_str_ptr2+1
    
@copy_cwd:
    lda (t_str_ptr2), y
    beq @cwd_done
    sta ARG_BUFF, x
    inx
    iny
    cpx #240
    bcc @copy_cwd
    
@cwd_done:
    cpx #0
    beq @append_filename
    lda #'/'
    sta ARG_BUFF, x
    inx
    
@append_filename:
    ldy #0
@copy_fname:
    lda filename_buf, y
    beq @path_done
    sta ARG_BUFF, x
    inx
    iny
    cpx #250
    bcc @copy_fname
    jmp @path_done
    
@abs_path:
    ldx #0
    ldy #0
@copy_abs:
    lda filename_buf, y
    beq @path_done
    sta ARG_BUFF, x
    inx
    iny
    cpx #250
    bcc @copy_abs

@path_done:
    lda #0
    sta ARG_BUFF, x
    inx
    
    ; 2. Calculate Length
    sec
    lda t_str_ptr1
    sbc #<text_buffer_fixed
    sta file_length_lo
    lda t_str_ptr1+1
    sbc #>text_buffer_fixed
    sta file_length_hi
    
    ; Append Length
    lda file_length_lo
    sta ARG_BUFF, x
    inx
    lda file_length_hi
    sta ARG_BUFF, x
    inx
    
    stx ARG_LEN
    
    ; 3. Send Command
    lda #<msg_saving
    ldy #>msg_saving
    jsr print_str_ay
    jsr CRLF
    
    lda #CMD_FS_SAVEMEM
    sta CMD_ID
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @start_stream
    
    lda #<msg_err
    ldy #>msg_err
    jsr print_str_ay
    jsr CRLF
    pla
    sta VIA_DDRA
    rts

@start_stream:
    ; 4. Stream Data
    lda #<stream_start_msg
    ldy #>stream_start_msg
    jsr print_str_ay
    
    ; Use FIXED buffer address
    lda #<text_buffer_fixed
    sta t_str_ptr2
    lda #>text_buffer_fixed
    sta t_str_ptr2+1
    
    ; Set VIA to Output
    lda #$FF
    sta VIA_DDRA
    
    ; Set up counters
    lda file_length_lo
    sta bytes_remaining_lo
    lda file_length_hi
    sta bytes_remaining_hi
    
    ; Check if empty
    lda bytes_remaining_lo
    ora bytes_remaining_hi
    beq @stream_done
    
    lda #'['
    jsr OUTCH
    
@stream_loop:
    ldy #0
    lda (t_str_ptr2), y
    jsr send_byte
    
    inc t_str_ptr2
    bne @no_inc_ptr
    inc t_str_ptr2+1
@no_inc_ptr:
    
    lda bytes_remaining_lo
    bne @dec_lo
    dec bytes_remaining_hi
@dec_lo:
    dec bytes_remaining_lo
    
    lda bytes_remaining_lo
    ora bytes_remaining_hi
    beq @stream_done
    
    lda bytes_remaining_lo
    cmp #$FF
    bne @stream_loop
    
    lda #'.'
    jsr OUTCH
    jmp @stream_loop

@stream_done:
    lda #']'
    jsr OUTCH
    jsr CRLF
    
    ; 5. Read Status
    lda #$00
    sta VIA_DDRA
    
    jsr read_byte
    pha
    jsr read_byte
    jsr read_byte
    pla
    
    cmp #STATUS_OK
    bne @final_err
    
    lda #<msg_done
    ldy #>msg_done
    jsr print_str_ay
    jsr CRLF
    
    pla
    sta VIA_DDRA
    rts

@final_err:
    lda #<msg_err
    ldy #>msg_err
    jsr print_str_ay
    jsr CRLF
    pla
    sta VIA_DDRA
    rts

; ---------------------------------------------------------------------------
; Helper: Print String
; ---------------------------------------------------------------------------
print_str_ay:
    sta t_str_ptr2
    sty t_str_ptr2+1
    ldy #0
@loop:
    lda (t_str_ptr2), y
    beq @done
    jsr OUTCH
    iny
    jmp @loop
@done:
    rts

; ---------------------------------------------------------------------------
; RODATA
; ---------------------------------------------------------------------------
.segment "RODATA"

ansi_cls:        .byte $1B, "[2J", $1B, "[H", 0
header_msg:      .asciiz "WRITE - Nano-like Editor "
no_file_msg:     .asciiz "[No File]"
separator_msg:   .asciiz "------------------------"
footer_msg:      .asciiz "^X Exit"
save_prompt:     .asciiz "Save modified buffer? (Y/N) "
filename_prompt: .asciiz "Filename: "
msg_saving:      .asciiz "Saving..."
msg_done:        .asciiz "Done"
msg_err:         .asciiz "Error"
stream_start_msg: .asciiz "Sending data: "

; ---------------------------------------------------------------------------
; BSS
; ---------------------------------------------------------------------------
.segment "BSS"

; Control variables
cwd_ptr:           .res 2
file_length_lo:    .res 1
file_length_hi:    .res 1
bytes_remaining_lo:.res 1
bytes_remaining_hi:.res 1
filename_buf:      .res 128

; FIXED SIZE TEXT BUFFER
text_buffer_fixed: .res 4096  ; 4KB fixed buffer
