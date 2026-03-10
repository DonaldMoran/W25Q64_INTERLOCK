; do.s - Execute a batch script
; Usage: DO <filename>

.include "pico_def.inc"

.import pico_send_request, send_byte, read_byte
.import CMD_ID, ARG_LEN, ARG_BUFF, LAST_STATUS

OUTCH = $FFEF
CRLF  = $FED1

t_ptr_temp = $5E
cwd_ptr    = $5E ; Re-use t_ptr_temp as it holds CWD pointer on entry
t_str_ptr1 = $5A ; Use for temp pointer during resolution
t_dest_ptr = $5C ; Pointer for writing batch buffer (replaces illegal $50 usage)

.segment "HEADER"
    .word $0800

.segment "CODE"
start:
    ; Preserve registers
    php
    pha
    txa
    pha
    tya
    pha

    ; Sanitize CPU state
    cld
    sei

    ; Save CWD pointer (passed in $5E/$5F) to a safe place if needed
    ; But we can just use it directly from $5E/$5F before we clobber it.
    ; Actually, we need $5E for other things later, so let's move CWD ptr to $5A (t_str_ptr1)
    ; No, let's just use it to build the path now.

    ; 1. Parse Filename
    ; Skip "RUN" and "EXECUTABLE" to find args
    ldx #0
    
    ; Skip Word 1 (RUN)
@skip_word_1:
    lda $0300, x
    bne @check_space_1_a
    jmp @no_args
@check_space_1_a:
    cmp #' '
    beq @found_space_1
    inx
    jmp @skip_word_1
@found_space_1:
    inx
    lda $0300, x
    bne @check_space_1_b
    jmp @no_args
@check_space_1_b:
    cmp #' '
    beq @found_space_1 ; Skip multiple spaces

    ; Skip Word 2 (Executable Path)
@skip_word_2:
    lda $0300, x
    bne @check_space_2_a
    jmp @no_args
@check_space_2_a:
    cmp #' '
    beq @found_space_2
    inx
    jmp @skip_word_2
@found_space_2:
    inx
    lda $0300, x
    bne @check_space_2_b
    jmp @no_args
@check_space_2_b:
    cmp #' '
    beq @found_space_2 ; Skip multiple spaces
    
    ; Resolve Path into ARG_BUFF
    ; Input: Command line at $0300,x
    ; CWD at ($5E)
    
    ; Check if arg starts with '/'
    lda $0300, x
    cmp #'/'
    beq @is_absolute
    
    ; Relative: Copy CWD first
    ldy #0
@copy_cwd:
    lda ($5E), y
    beq @cwd_done
    sta ARG_BUFF, y
    iny
    jmp @copy_cwd
@cwd_done:
    ; Check if we need a separator (if CWD is not just "/")
    cpy #1
    beq @append_arg ; If len is 1, it's likely "/", so don't add another
    lda #'/'
    sta ARG_BUFF, y
    iny
    
@append_arg:
    ; Now append the argument
    ; X is index into $0300
@copy_rel_loop:
    lda $0300, x
    beq @arg_done
    cmp #' '
    beq @arg_done
    sta ARG_BUFF, y
    inx
    iny
    jmp @copy_rel_loop

@is_absolute:
    ldy #0
    jmp @copy_rel_loop ; Just copy arg to ARG_BUFF

@arg_done:
    lda #0
    sta ARG_BUFF, y
    sty ARG_LEN

    ; 2. Load File to BATCH_BUFFER ($3000)
    ; We use CMD_FS_LOADMEM to stream the file
    lda #CMD_FS_LOADMEM
    sta CMD_ID
    
    ; Manually send request to handle streaming
    lda #$FF
    sta VIA_DDRA ; DDRA Output
    
    lda CMD_ID
    jsr send_byte
    lda ARG_LEN
    jsr send_byte
    
    ldx #0
@send_args:
    lda ARG_BUFF, x
    jsr send_byte
    inx
    cpx ARG_LEN
    bne @send_args
    
    ; Read Response
    lda #$00
    sta VIA_DDRA ; DDRA Input
    
    jsr read_byte ; Status
    cmp #STATUS_OK
    beq @load_ok
    
    ; Error
    jsr read_byte ; len lo
    jsr read_byte ; len hi
    jmp @load_fail

@load_ok:
    jsr read_byte ; len lo
    sta t_ptr_temp
    jsr read_byte ; len hi
    sta t_ptr_temp+1
    
    ; Stream data to BATCH_BUFFER
    lda #<BATCH_BUFFER
    sta t_dest_ptr
    lda #>BATCH_BUFFER
    sta t_dest_ptr+1
    
@stream_loop:
    lda t_ptr_temp
    ora t_ptr_temp+1
    beq @stream_done
    
    jsr read_byte
    ldy #0
    sta (t_dest_ptr), y
    
    inc t_dest_ptr
    bne @no_inc
    inc t_dest_ptr+1
@no_inc:
    
    lda t_ptr_temp
    bne @dec_lo
    dec t_ptr_temp+1
@dec_lo:
    dec t_ptr_temp
    jmp @stream_loop

@stream_done:
    ; Null terminate the script
    lda #0
    sta (t_dest_ptr), y
    
    ; 3. Activate Batch Mode
    lda #<BATCH_BUFFER
    sta BATCH_PTR
    lda #>BATCH_BUFFER
    sta BATCH_PTR+1
    
    ; Restore and return
    lda #$FF
    sta VIA_DDRA ; Restore DDRA
    
    pla
    tay
    pla
    tax
    pla
    plp
    clc
    rts

@load_fail:
    lda #$FF
    sta VIA_DDRA
    
    lda #<msg_fail
    sta t_str_ptr1
    lda #>msg_fail
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    
    jmp @error

@no_args:
@error:
    lda #$FF
    sta VIA_DDRA
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

.segment "RODATA"
msg_fail: .asciiz "LOAD FAILED"