; tail.s - Print last 10 lines of a file
; Usage: TAIL <filename>

.include "../../common/pico_def.inc"

.import read_byte, send_byte
.import ARG_BUFF

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
INPUT_BUFFER = $0300
ACIA_DATA    = $5000
READ_CHUNK_SIZE = 512 ; Read last 512 bytes

; ---------------------------------------------------------------------------
; Zero Page (Transient Safe Area $58-$5F)
; ---------------------------------------------------------------------------
t_ptr_temp   = $58 ; 2 bytes
t_handle     = $5A ; 1 byte
t_lines      = $5B ; 1 byte
t_bytes_read = $5C ; 2 bytes
t_cwd_ptr    = $5E ; 2 bytes (passed by shell, reused)

; ---------------------------------------------------------------------------
; System calls
; ---------------------------------------------------------------------------
OUTCH  = $FFEF
CRLF   = $FED1

.segment "HEADER"
    .word $0800

.segment "BSS"
read_buf:   .res 512
file_size:  .res 4
seek_offset:.res 4

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

    ; Skip "RUN" and "/BIN/TAIL.BIN"
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
    
    ; Read Size (4 bytes)
    jsr read_byte
    sta file_size
    jsr read_byte
    sta file_size+1
    jsr read_byte
    sta file_size+2
    jsr read_byte
    sta file_size+3
    
    lda #$FF
    sta VIA_DDRA

    ; -----------------------------------------------------------------------
    ; Calculate Seek Offset (Size - 512)
    ; -----------------------------------------------------------------------
    lda file_size
    sec
    sbc #<READ_CHUNK_SIZE
    sta seek_offset
    
    lda file_size+1
    sbc #>READ_CHUNK_SIZE
    sta seek_offset+1
    
    lda file_size+2
    sbc #0
    sta seek_offset+2
    
    lda file_size+3
    sbc #0
    sta seek_offset+3
    
    ; Check for borrow (Carry Clear = Borrow occurred, meaning Size < 512)
    bcs @seek_ready
    
    ; Underflow: Seek to 0
    lda #0
    sta seek_offset
    sta seek_offset+1
    sta seek_offset+2
    sta seek_offset+3

@seek_ready:
    ; Send CMD_FS_SEEK
    lda #CMD_FS_SEEK
    jsr send_byte
    
    lda #6          ; Arg len (Handle + 4 byte offset + 1 byte whence)
    jsr send_byte
    
    lda t_handle
    jsr send_byte
    
    lda seek_offset
    jsr send_byte
    lda seek_offset+1
    jsr send_byte
    lda seek_offset+2
    jsr send_byte
    lda seek_offset+3
    jsr send_byte
    
    lda #0          ; Whence = SEEK_SET (0)
    jsr send_byte
    
    ; Read Response (Ignore new position)
    lda #$00
    sta VIA_DDRA
    jsr read_byte   ; Status
    pha             ; Save status
    jsr read_byte ; Len Lo
    jsr read_byte ; Len Hi
    pla             ; Restore status
    cmp #STATUS_OK
    bne @seek_fail

    jsr read_byte ; Pos 0
    jsr read_byte ; Pos 1
    jsr read_byte ; Pos 2
    jsr read_byte ; Pos 3
    
    lda #$FF
    sta VIA_DDRA

    ; -----------------------------------------------------------------------
    ; Read Chunk
    ; -----------------------------------------------------------------------
    lda #CMD_FS_READ
    jsr send_byte
    
    lda #3          ; Arg len
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

@seek_fail:
    lda #$FF
    sta VIA_DDRA
    jmp @close_file

@read_ok:
    jsr read_byte   ; Len Lo
    sta t_bytes_read
    jsr read_byte   ; Len Hi
    sta t_bytes_read+1
    
    ; Read Data into buffer
    ; We use t_ptr_temp as index (16-bit)
    lda #0
    sta t_ptr_temp
    sta t_ptr_temp+1
    
@data_loop:
    lda t_bytes_read
    ora t_bytes_read+1
    beq @data_done
    
    jsr read_byte
    pha             ; Save data byte
    
    ; Store in read_buf
    ldx t_ptr_temp ; Low byte index
    lda t_ptr_temp+1
    bne @store_hi
    pla             ; Restore data byte
    sta read_buf, x
    jmp @dec_cnt
@store_hi:
    pla             ; Restore data byte
    sta read_buf+256, x
    
@dec_cnt:
    ; Increment index
    inc t_ptr_temp
    bne @no_inc_idx
    inc t_ptr_temp+1
@no_inc_idx:

    ; Decrement count
    lda t_bytes_read
    bne @dec_lo
    dec t_bytes_read+1
@dec_lo:
    dec t_bytes_read
    jmp @data_loop

@data_done:
    lda #$FF
    sta VIA_DDRA
    
    ; Save total bytes read into seek_offset for print loop limit
    lda t_ptr_temp
    sta seek_offset
    lda t_ptr_temp+1
    sta seek_offset+1

    ; -----------------------------------------------------------------------
    ; Scan Backwards
    ; -----------------------------------------------------------------------
    ; t_ptr_temp holds total bytes read.
    ; We want to scan from t_ptr_temp - 1 down to 0.
    
    ; Check if empty
    lda t_ptr_temp
    ora t_ptr_temp+1
    beq @close_file
    
    ; Start at end - 1
    lda t_ptr_temp
    bne @dec_ptr
    dec t_ptr_temp+1
@dec_ptr:
    dec t_ptr_temp
    
    ; t_lines = 10
    lda #0
    sta t_bytes_read ; Use as newline counter
    
@scan_loop:
    ; Load char at t_ptr_temp
    ldx t_ptr_temp ; Low byte
    lda t_ptr_temp+1
    bne @load_hi
    lda read_buf, x
    jmp @check_char
@load_hi:
    lda read_buf+256, x
    
@check_char:
    cmp #$0A ; Newline
    bne @next_char
    
    ; Found newline.
    ; If this is the very last character of the buffer, ignore it for counting?
    ; Logic: If we find a newline, it terminates the line BEFORE it.
    ; We want to find the start of the 10th line from the end.
    ; That start is at (10th newline pos) + 1.
    
    ; Check if this is the last char in buffer?
    ; No, simpler: just count.
    inc t_bytes_read
    lda t_bytes_read
    cmp #11 ; Found 11th newline? (Start of 10th line is after 10th newline?)
            ; If file ends in \n, we find 11 \n's to get 10 lines.
            ; If file doesn't end in \n, we find 10 \n's.
            ; Let's stick to 11 for safety/standard behavior with trailing \n.
    beq @found_start
    
@next_char:
    ; Decrement pointer
    lda t_ptr_temp
    bne @dec_scan
    lda t_ptr_temp+1
    beq @print_all ; Reached start of buffer (0)
    dec t_ptr_temp+1
@dec_scan:
    dec t_ptr_temp
    jmp @scan_loop

@found_start:
    ; t_ptr_temp points to the newline BEFORE our desired start.
    ; So start printing at t_ptr_temp + 1.
    inc t_ptr_temp
    bne @print_loop
    inc t_ptr_temp+1
    jmp @print_loop

@print_all:
    ; Reset pointer to 0
    lda #0
    sta t_ptr_temp
    sta t_ptr_temp+1

@print_loop:
    ; Check if we hit the end of data (stored in file_size temporarily? No, we lost total read count)
    ; We need to know where the buffer ends.
    ; We can re-read the length from the file read response? No.
    ; We should have saved the total bytes read.
    ; Let's assume we read until we hit a 0? No, binary files.
    ; Let's save total read count in t_count before scanning.
    ; But t_count is used.
    ; Let's use seek_offset (4 bytes) to store the read count since we are done seeking.
    ; (Actually we can just look for null terminator if we null terminated? No buffer full).
    
    ; REVISION: Save total read count in seek_offset (low 2 bytes) before scanning.
    ; (See modification below)
    
    ; Compare t_ptr_temp with seek_offset
    lda t_ptr_temp
    cmp seek_offset
    bne @do_print
    lda t_ptr_temp+1
    cmp seek_offset+1
    beq @close_file ; Done
    
@do_print:
    ldx t_ptr_temp
    lda t_ptr_temp+1
    bne @pr_hi
    lda read_buf, x
    jmp @pr_char
@pr_hi:
    lda read_buf+256, x
@pr_char:
    jsr OUTCH
    
    inc t_ptr_temp
    bne @print_loop
    inc t_ptr_temp+1
    jmp @print_loop

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
msg_usage: .asciiz "Usage: TAIL <filename>"
msg_fail:  .asciiz "Error: File not found"