; put.s - Full working PUT command for DDOS shell
; Location: 6502/ca65/commands/put/put.s

; ---------------------------------------------------------------------------
; External symbols
; ---------------------------------------------------------------------------
.import pico_send_request
.import CMD_ID, ARG_LEN, ARG_BUFF, LAST_STATUS, RESP_LEN, RESP_BUFF

; ---------------------------------------------------------------------------
; System calls
; ---------------------------------------------------------------------------
OUTCH = $FFEF    ; Print character in A
OUTHEX = $FFDC   ; Print hex byte in A
CRLF  = $FED1    ; Print CR/LF

; ---------------------------------------------------------------------------
; Zero page - Using shell's ptr_temp ($56-$57) which is saved/restored
; ---------------------------------------------------------------------------
ptr_temp = $56   ; 2 bytes - Shell's temporary pointer (safe to use)

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
CMD_FS_OPEN       = $12
CMD_FS_READ       = $13
CMD_FS_CLOSE      = $1C
CMD_FS_STAT       = $1F
CMD_NET_HTTP_POST = $35

STATUS_OK      = $00
STATUS_ERR     = $01
STATUS_NO_FILE = $02

INPUT_BUFFER  = $0300

; ---------------------------------------------------------------------------
; HEADER
; ---------------------------------------------------------------------------
.segment "HEADER"
    .word $0800

; ---------------------------------------------------------------------------
; CODE
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

    ; Save CWD pointer from shell ($5E/$5F)
    lda $5E
    sta cwd_ptr
    lda $5F
    sta cwd_ptr+1

    ; -----------------------------------------------------------------------
    ; 1. Parse Arguments - Handle "RUN /BIN/PUT.BIN filename" format
    ; -----------------------------------------------------------------------
    ldx #0
    
    ; Skip first word (RUN)
@skip_run:
    lda INPUT_BUFFER, x
    beq @goto_usage1
    cmp #' '
    beq @skip_run_space
    inx
    jmp @skip_run
@goto_usage1:
    jmp usage
    
@skip_run_space:
    inx
    
    ; Skip second word (/BIN/PUT.BIN)
@skip_path:
    lda INPUT_BUFFER, x
    beq @goto_usage2
    cmp #' '
    beq @skip_path_space
    inx
    jmp @skip_path
@goto_usage2:
    jmp usage
    
@skip_path_space:
    inx
    
    ; Skip any spaces before filename
@skip_spaces:
    lda INPUT_BUFFER, x
    beq @goto_usage3
    cmp #' '
    bne @found_local
    inx
    jmp @skip_spaces
@goto_usage3:
    jmp usage
    
@found_local:
    ; X now points to start of local filename
    stx local_start
    
    ; Find end of local filename
    ldy #0
@find_local_end:
    lda INPUT_BUFFER, x
    beq @local_done
    cmp #' '
    beq @local_done
    inx
    iny
    jmp @find_local_end
@local_done:
    sty local_len
    
    ; Check for remote filename argument
    lda INPUT_BUFFER, x
    beq @no_remote
    inx
    lda INPUT_BUFFER, x
    beq @no_remote
    cmp #' '
    beq @no_remote
    stx remote_start
    
    ldy #0
@find_remote_end:
    lda INPUT_BUFFER, x
    beq @remote_done
    cmp #' '
    beq @remote_done
    inx
    iny
    jmp @find_remote_end
@remote_done:
    sty remote_len
    jmp @args_parsed
    
@no_remote:
    lda #0
    sta remote_len
    sta remote_start

@args_parsed:

    ; -----------------------------------------------------------------------
    ; 2. Verify local file exists using CMD_FS_STAT
    ; -----------------------------------------------------------------------
    ldx #0
    jsr resolve_local_path
    lda #0
    sta ARG_BUFF, x
    inx
    stx ARG_LEN
    
    ; Send STAT command
    lda #CMD_FS_STAT
    sta CMD_ID
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @file_exists
    
    lda #<msg_no_file
    sta ptr_temp
    lda #>msg_no_file
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    jmp done

@file_exists:

    ; -----------------------------------------------------------------------
    ; 3. Read server.cfg
    ; -----------------------------------------------------------------------
    lda #CMD_FS_OPEN
    sta CMD_ID
    
    ; Copy "/server.cfg" to ARG_BUFF
    lda #'/'
    sta ARG_BUFF
    lda #'s'
    sta ARG_BUFF+1
    lda #'e'
    sta ARG_BUFF+2
    lda #'r'
    sta ARG_BUFF+3
    lda #'v'
    sta ARG_BUFF+4
    lda #'e'
    sta ARG_BUFF+5
    lda #'r'
    sta ARG_BUFF+6
    lda #'.'
    sta ARG_BUFF+7
    lda #'c'
    sta ARG_BUFF+8
    lda #'f'
    sta ARG_BUFF+9
    lda #'g'
    sta ARG_BUFF+10
    lda #0
    sta ARG_BUFF+11
    
    lda #12
    sta ARG_LEN
    
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @open_ok
    
    lda #<msg_no_cfg
    sta ptr_temp
    lda #>msg_no_cfg
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    jmp done

@open_ok:
    ; Save handle
    lda RESP_BUFF
    sta file_handle
    
    ; Read file
    lda #CMD_FS_READ
    sta CMD_ID
    lda file_handle
    sta ARG_BUFF
    lda #32
    sta ARG_BUFF+1
    lda #0
    sta ARG_BUFF+2
    lda #3
    sta ARG_LEN
    
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @read_ok
    
    lda #<msg_bad_cfg
    sta ptr_temp
    lda #>msg_bad_cfg
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    jmp close_file

@read_ok:
    ; Copy response to buffer
    ldx #0
@copy_resp:
    cpx RESP_LEN
    bcs @copy_done
    lda RESP_BUFF, x
    sta cfg_data, x
    inx
    jmp @copy_resp
@copy_done:
    lda #0
    sta cfg_data, x
    
    ; Find colon and split
    ldx #0
@find_colon:
    lda cfg_data, x
    beq cfg_invalid
    cmp #':'
    beq colon_found
    inx
    jmp @find_colon
    
cfg_invalid:
    jmp close_and_fail

colon_found:
    lda #0
    sta cfg_data, x
    stx cfg_ip_len
    inx
    stx cfg_port_start

close_file:
    ; Close file
    lda #CMD_FS_CLOSE
    sta CMD_ID
    lda file_handle
    sta ARG_BUFF
    lda #1
    sta ARG_LEN
    jsr pico_send_request

    ; -----------------------------------------------------------------------
    ; 4. Build request packet in ARG_BUFF
    ; Format: IP\0Port\0LocalPath\0RemotePath
    ; -----------------------------------------------------------------------
    ldx #0
    
    ; Copy IP
    ldy #0
@copy_ip:
    lda cfg_data, y
    beq @ip_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_ip
@ip_done:
    lda #0
    sta ARG_BUFF, x
    inx
    
    ; Copy Port
    ldy cfg_port_start
@copy_port:
    lda cfg_data, y
    beq @port_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_port
@port_done:
    lda #0
    sta ARG_BUFF, x
    inx
    
    ; Copy Local Path
    jsr resolve_local_path
    lda #0
    sta ARG_BUFF, x
    inx
    
    ; Copy Remote Path
    lda remote_len
    beq @use_local_name
    
    ; Use provided remote path
    ldy remote_start
@copy_remote:
    lda INPUT_BUFFER, y
    beq @remote_done
    cmp #' '
    beq @remote_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_remote
@remote_done:
    ; Check if remote path ends in '/'
    dex
    lda ARG_BUFF, x
    inx
    cmp #'/'
    beq @append_basename_only
    lda #0
    sta ARG_BUFF, x
    inx
    jmp @packet_done

@use_local_name:
    ; Use filename from local path (basename), prepend /
    lda #'/'
    sta ARG_BUFF, x
    inx
@append_basename_only:

    ; Find start of basename in INPUT_BUFFER
    ldy local_start
    sty ptr_temp ; Store start index
    
@find_basename:
    lda INPUT_BUFFER, y
    beq @basename_found
    cmp #' '
    beq @basename_found
    cmp #'/'
    bne @next_char
    sty ptr_temp ; Found a slash, update start index
    inc ptr_temp ; Point to char after slash
@next_char:
    iny
    jmp @find_basename

@basename_found:
    ldy ptr_temp
@copy_basename:
    lda INPUT_BUFFER, y
    beq @remote_local_done
    cmp #' '
    beq @remote_local_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_basename
@remote_local_done:
    lda #0
    sta ARG_BUFF, x
    inx

@packet_done:
    stx ARG_LEN

    ; -----------------------------------------------------------------------
    ; 5. Send HTTP POST command
    ; -----------------------------------------------------------------------
    lda #<msg_uploading
    sta ptr_temp
    lda #>msg_uploading
    sta ptr_temp+1
    jsr print_string
    jsr CRLF

    lda #CMD_NET_HTTP_POST
    sta CMD_ID
    jsr pico_send_request
    
    lda LAST_STATUS
    bne @upload_failed
    
    lda #<msg_done
    sta ptr_temp
    lda #>msg_done
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    jmp done

@upload_failed:
    lda #<msg_err
    sta ptr_temp
    lda #>msg_err
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    jmp done

usage:
    lda #<msg_usage
    sta ptr_temp
    lda #>msg_usage
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    jmp done

done:
    pla
    tay
    pla
    tax
    pla
    plp
    clc
    rts

close_and_fail:
    lda #<msg_bad_cfg
    sta ptr_temp
    lda #>msg_bad_cfg
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    jmp close_file

; ---------------------------------------------------------------------------
; resolve_local_path
; Copies local path from INPUT_BUFFER to ARG_BUFF at index X.
; Resolves relative paths using CWD.
; Updates X to point after the copied string.
; ---------------------------------------------------------------------------
resolve_local_path:
    ldy local_start
    lda INPUT_BUFFER, y
    cmp #'/'
    beq @copy_abs

    ; Relative path - prepend CWD
    lda cwd_ptr
    sta ptr_temp
    lda cwd_ptr+1
    sta ptr_temp+1
    
    ldy #0
@copy_cwd:
    lda (ptr_temp), y
    beq @cwd_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_cwd
@cwd_done:
    ; Add slash if needed (unless CWD is just "/")
    ldy #0
    lda (ptr_temp), y
    cmp #'/'
    bne @add_slash
    ldy #1
    lda (ptr_temp), y
    beq @start_local ; CWD is "/", don't add another slash
@add_slash:
    lda #'/'
    sta ARG_BUFF, x
    inx

@start_local:
    ldy local_start
@copy_abs:
    lda INPUT_BUFFER, y
    beq @done
    cmp #' '
    beq @done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_abs
@done:
    rts

; ---------------------------------------------------------------------------
; Print string using ptr_temp ($56-$57)
; ---------------------------------------------------------------------------
print_string:
    pha
    phy
    ldy #0
@loop:
    lda (ptr_temp), y
    beq @done
    jsr OUTCH
    iny
    jmp @loop
@done:
    ply
    pla
    rts

; ---------------------------------------------------------------------------
; RODATA
; ---------------------------------------------------------------------------
.segment "RODATA"

filename_cfg:    .asciiz "/server.cfg"
msg_usage:       .asciiz "Usage: PUT <local_file> [remote_file]"
msg_uploading:   .asciiz "Uploading..."
msg_done:        .asciiz "Done"
msg_err:         .asciiz "Upload failed"
msg_no_file:     .asciiz "Error: Local file not found"
msg_no_cfg:      .asciiz "Error: Run SETSERVER first"
msg_bad_cfg:     .asciiz "Error: Invalid server.cfg"

; ---------------------------------------------------------------------------
; BSS
; ---------------------------------------------------------------------------
.segment "BSS"

cwd_ptr:         .res 2   ; Saved CWD pointer
file_handle:     .res 1   ; File handle for server.cfg
cfg_data:        .res 32  ; Buffer for server.cfg contents
cfg_ip_len:      .res 1   ; Length of IP part
cfg_port_start:  .res 1   ; Start index of port
local_start:     .res 1   ; Start of local path in INPUT_BUFFER
local_len:       .res 1   ; Length of local path
remote_start:    .res 1   ; Start of remote path (0 if none)
remote_len:      .res 1   ; Length of remote path (0 if none)
