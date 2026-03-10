; setserver.s - Set or get the file server address
; Location: 6502/ca65/commands/setserver/setserver.s

; ---------------------------------------------------------------------------
; External symbols
; ---------------------------------------------------------------------------
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
t_str_ptr2   = $5C  ; 2 bytes - String pointer 2
t_ptr_temp   = $5E  ; 2 bytes - Temporary pointer (File Handle)

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
CMD_FS_OPEN   = $12
CMD_FS_READ   = $13
CMD_FS_CLOSE  = $1C
CMD_FS_SAVEMEM = $23

STATUS_OK      = $00
STATUS_ERR     = $01
STATUS_NO_FILE = $02

INPUT_BUFFER  = $0300
VIA_DDRA      = $6003

; ---------------------------------------------------------------------------
; Imported from pico_lib
; ---------------------------------------------------------------------------
.import send_byte, read_byte

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
    ; ALWAYS preserve registers
    php
    pha
    txa
    pha
    tya
    pha

    ; Sanitize CPU state
    cld
    sei

    ; -----------------------------------------------------------------------
    ; Parse Arguments
    ; -----------------------------------------------------------------------
    ; Scan INPUT_BUFFER for the first space to skip command name
    ldx #0
@scan_cmd:
    lda INPUT_BUFFER, x
    beq @get_mode       ; End of line found before space -> GET mode
    cmp #' '
    beq @skip_spaces
    inx
    bne @scan_cmd       ; Safety limit
    jmp @get_mode       ; Should not happen

@skip_spaces:
    inx
    lda INPUT_BUFFER, x
    beq @get_mode       ; End of line -> GET mode
    cmp #' '
    beq @skip_spaces
    
    ; Found argument start at index X
    ; Save pointer to argument in t_arg_ptr
    txa
    clc
    adc #<INPUT_BUFFER
    sta t_arg_ptr
    lda #>INPUT_BUFFER
    adc #0
    sta t_arg_ptr+1
    
    ; Always skip the first argument (the executable path from RUN)

    ; Skip this argument (the path)
@skip_path:
    iny
    lda (t_arg_ptr), y
    beq @get_mode       ; End of line -> GET mode
    cmp #' '
    bne @skip_path

@skip_spaces_2:
    iny
    lda (t_arg_ptr), y
    beq @get_mode       ; End of line -> GET mode
    cmp #' '
    beq @skip_spaces_2

    ; Found real argument, update t_arg_ptr
    tya
    clc
    adc t_arg_ptr
    sta t_arg_ptr
    bcc @go_set
    inc t_arg_ptr+1
@go_set:
    jmp set_mode

; ---------------------------------------------------------------------------
; GET MODE: Read and display server.cfg
; ---------------------------------------------------------------------------
@get_mode:
    ; 1. Open File
    lda #CMD_FS_OPEN
    sta CMD_ID
    
    ; Copy filename to ARG_BUFF
    ldy #0
@copy_fname_get:
    lda filename, y
    sta ARG_BUFF, y
    beq @fname_done_get
    iny
    bne @copy_fname_get
@fname_done_get:
    sty ARG_LEN
    
    jsr pico_send_request
    
    ; Check status
    lda LAST_STATUS
    cmp #STATUS_NO_FILE
    beq @no_file
    cmp #STATUS_OK
    bne @error
    
    ; Save Handle (RESP_BUFF[0])
    lda RESP_BUFF
    sta t_ptr_temp      ; Store handle in ZP
    
    ; 2. Read File
    ; CMD_FS_READ (Handle, LenLO, LenHI)
    lda #CMD_FS_READ
    sta CMD_ID
    
    lda t_ptr_temp
    sta ARG_BUFF        ; Handle
    
    lda #255            ; Read up to 255 bytes
    sta ARG_BUFF+1
    lda #0
    sta ARG_BUFF+2
    
    lda #3
    sta ARG_LEN
    
    jsr pico_send_request
    
    lda LAST_STATUS
    bne @close_and_err
    
    ; 3. Print Result
    lda #<msg_current
    sta t_str_ptr1
    lda #>msg_current
    sta t_str_ptr1+1
    jsr print_string
    
    ; Print content from RESP_BUFF
    ldx #0
@print_loop:
    cpx RESP_LEN
    bcs @print_done
    lda RESP_BUFF, x
    beq @print_done     ; Stop at null if present
    jsr OUTCH
    inx
    bne @print_loop
@print_done:
    jsr CRLF
    
    ; 4. Close File
    jmp close_file

@no_file:
    lda #<msg_none
    sta t_str_ptr1
    lda #>msg_none
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    jmp done

@error:
    jmp print_error

@close_and_err:
    jsr close_file_sub
    jmp print_error

; ---------------------------------------------------------------------------
; SET MODE: Write argument to server.cfg
; ---------------------------------------------------------------------------
set_mode:
    ; Calculate length of the argument string
    ldy #0
@calc_len:
    lda (t_arg_ptr), y
    beq @len_done
    cmp #' '
    beq @len_done
    iny
    bne @calc_len
@len_done:
    ; Y contains length. Save it.
    sty t_ptr_temp      ; Low byte of length
    lda #0
    sta t_ptr_temp+1    ; High byte of length (always 0 for short string)

    ; -----------------------------------------------------------------------
    ; Prepare CMD_FS_SAVEMEM
    ; Args: [Filename] \0 [LenLO] [LenHI]
    ; -----------------------------------------------------------------------
    lda #CMD_FS_SAVEMEM
    sta CMD_ID
    
    ; 1. Copy filename to ARG_BUFF
    ldy #0
@copy_fname:
    lda filename, y
    sta ARG_BUFF, y
    beq @fname_done
    iny
    bne @copy_fname
@fname_done:
    ; Y points to null terminator. Increment to point after it.
    iny
    
    ; 2. Append Length (Little Endian)
    lda t_ptr_temp      ; Len LO
    sta ARG_BUFF, y
    iny
    lda t_ptr_temp+1    ; Len HI
    sta ARG_BUFF, y
    iny
    
    sty ARG_LEN
    
    ; 3. Send Command
    jsr pico_send_request
    
    ; 4. Check Initial Status (Ready to stream?)
    lda LAST_STATUS
    bne @error
    
    ; -----------------------------------------------------------------------
    ; Stream Data
    ; -----------------------------------------------------------------------
    ldy #0
@stream_loop:
    cpy t_ptr_temp      ; Compare with length
    beq @stream_done
    
    lda (t_arg_ptr), y
    jsr send_byte
    iny
    bne @stream_loop
@stream_done:

    ; -----------------------------------------------------------------------
    ; Read Final Status
    ; -----------------------------------------------------------------------
    ; Switch to Input to read response
    lda #$00
    sta VIA_DDRA

    ; The Pico sends [Status] [LenLO] [LenHI] after streaming is done
    jsr read_byte
    sta LAST_STATUS
    jsr read_byte       ; Ignore LenLO
    jsr read_byte       ; Ignore LenHI

    ; Restore Output
    lda #$FF
    sta VIA_DDRA

    lda LAST_STATUS
    bne @error
    
    ; 4. Success Message
    lda #<msg_set
    sta t_str_ptr1
    lda #>msg_set
    sta t_str_ptr1+1
    jsr print_string
    
    ; Print what we set it to (re-use t_arg_ptr)
    ldy #0
@print_arg:
    lda (t_arg_ptr), y
    beq @print_arg_done
    cmp #' '
    beq @print_arg_done
    jsr OUTCH
    iny
    bne @print_arg
@print_arg_done:
    jsr CRLF
    jmp done

@error:
    jmp print_error

; ---------------------------------------------------------------------------
; Helper: Close File
; ---------------------------------------------------------------------------
close_file:
    jsr close_file_sub
    jmp done

close_file_sub:
    lda #CMD_FS_CLOSE
    sta CMD_ID
    lda t_ptr_temp
    sta ARG_BUFF
    lda #1
    sta ARG_LEN
    jsr pico_send_request
    rts

; ---------------------------------------------------------------------------
; Helper: Print Error
; ---------------------------------------------------------------------------
print_error:
    lda #<msg_err
    sta t_str_ptr1
    lda #>msg_err
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    jmp done

; ---------------------------------------------------------------------------
; Helper: Print null-terminated string
; ---------------------------------------------------------------------------
print_string:
    pha
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
    pla
    rts

; ---------------------------------------------------------------------------
; Exit
; ---------------------------------------------------------------------------
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
; RODATA
; ---------------------------------------------------------------------------
.segment "RODATA"

filename:    .asciiz "server.cfg"
msg_current: .asciiz "Current server: "
msg_set:     .asciiz "Server set to "
msg_none:    .asciiz "No server set"
msg_err:     .asciiz "Error"